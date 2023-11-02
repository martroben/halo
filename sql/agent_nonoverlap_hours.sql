/*
Report of agent worked hours per day in a way that the overlapping hours are not double-counted.

##################
# RESULT COLUMNS #
##################

Agent               Agent name
Date                Day
HoursLogged         Non-overlapping hours from all actions that ended on that day


#########################
# TABLES & COLUMNS USED #
#########################

ACTIONS             All Agent actions logged under tickets
.Faultid            Ticket id
.actionnumber       Action sequence number under the ticket
.who                Agent name
.whoagentid         Agent id
.ActionArrivalDate  Action logged time start
.ActionCompletionDate Action logged time end

UNAME               Halo dashboard user info (technicians)
.UName              User name
.UNum               User id

CALENDAR            Table of dates
.date_id            Date identifier in YYYY/mm/dd format


#########################################
# CTE-s USED (Common Table Expressions) #
#########################################

DaysCTE                 List of all dates in a range
DayFillerCTE            List of agents with each having a list of dates

AS ActonDatesCTE        Actions and action dates
EventIndicesCTE         Action start and end times with 1 or -1 as index
CumulativeIndicesCTE    Action start and end times with cumulative sum over indices
IndicesCTE              Action start and end times with previous row cumulative sum column added
WorkBlockEventsCTE      Action start and end times with a column for which are start end or overlap events in workblocks
WorkBlockCTE            Workblock start and end times
WorkBlockDurationsCTE   Workblock start and end times with durations


####################
# HARDCODED VALUES #
####################

CAST(<block duration> AS Decimal(18,2))                     Workblock duration is given with two decimal place precision.
WHERE CAST(date_id AS date) <= DATEADD(DAY, 7, GETDATE())   Only workblocks up to 7 days into the future are given

*/

/* 9. Sum workblock durations by agent and by day */
SELECT
    DayFillerCTE.Uname AS Agent,
    DayFillerCTE.Day AS Date,
    SUM(WorkBlockDurationsCTE.DurationHours) AS HoursLogged
FROM
    /* 7. Add timeblock duration column */
    (SELECT
        *,
        CAST(BlockEnd AS date) AS EventDay,
        CAST(ROUND(DATEDIFF(second, BlockStart, BlockEnd) / 3600.0, 2) AS Decimal(18,2)) AS DurationHours
    FROM
        /* 6. Discard all 'overlap' events.
        Pivot each following start and end event back to a single row to get timeblocks */
        (SELECT
            /* Have to select specific columns for pivot */
            EventTime,
            who,
            whoagentid,
            WorkBlockEvent,
            /* Give same index to each two rows following each other to group same workblock events */
            (ROW_NUMBER() OVER(PARTITION BY whoagentid ORDER BY EventTime) - 1) / 2 AS AgentWorkBlockIndex
        FROM
            /* 5. Detect time block start and end rows.
            Timeblock start conditions:
                EventIndex = 1 - action start
                CumulativeIndex > 0
                previous row CumulativeIndex = 0 or NULL - excludes rows where start and end of different events are on the same time
            Timeblock end conditions:
                EventIndex = -1 - action end
                CumulativeIndex = 0
                previous row CumulativeIndex is not 0 or NULL - excludes cases where data starts with end event. */
            (SELECT
                *,
                CASE
                    WHEN EventIndex = 1 AND CumulativeIndex > 0 AND ISNULL(CumulativeIndexLag, 0) = 0 THEN 'BlockStart'
                    WHEN EventIndex = -1 AND CumulativeIndex = 0 AND ISNULL(CumulativeIndexLag, 0) <> 0 THEN 'BlockEnd'
                    ELSE 'overlap'
                END AS WorkBlockEvent
            FROM
                /* 4. Add previous row cumulative sum to each row */
                (SELECT
                    *,
                    LAG(CumulativeIndex) OVER (PARTITION BY whoagentid ORDER BY EventTime) CumulativeIndexLag
                FROM
                    /* 3. Add cumulative sum over the start/end indices (partitioned by agent). */
                    (SELECT
                        *,
                        SUM(EventIndex)
                            OVER (PARTITION BY whoagentid ORDER BY EventTime) AS CumulativeIndex
                    FROM
                        /* 2. Pivot action start and end times to separate rows.
                        Assign index 1 to each start time and -1 to each end time. */
                        (SELECT
                            *,
                            CASE
                                WHEN Event = 'ActionArrivalDate' THEN 1
                                WHEN Event = 'ActionCompletionDate' THEN -1
                                ELSE 0
                            END AS EventIndex
                        FROM
                            /* 1. Select all actions with their start and end times */
                            (SELECT
                                ACTIONS.Faultid,
                                ACTIONS.actionnumber,
                                ACTIONS.who,
                                ACTIONS.whoagentid,
                                ACTIONS.ActionArrivalDate,
                                ACTIONS.ActionCompletionDate
                                /* For future extensions
                                ACTIONS.ActionChargeHours,
                                ACTIONS.ActionNonChargeHours
                                */
                            FROM
                                ACTIONS
                            WHERE
                                /* Remove zero-duration actions */
                                ACTIONS.ActionArrivalDate <> ACTIONS.ActionCompletionDate
                            ) AS ActonDatesCTE
                        UNPIVOT
                            (EventTime
                            FOR Event IN (ActionArrivalDate, ActionCompletionDate)
                            ) AS ActionDatesUnpivot
                        ) AS EventIndicesCTE
                    ) AS CumulativeIndicesCTE
                ) AS IndicesCTE
            ) AS WorkBlockEventsCTE
        WHERE WorkBlockEvent <> 'overlap'
        ) AS WorkBlockCTE
    PIVOT
        (MAX(EventTime)
        FOR WorkBlockEvent IN ([BlockStart], [BlockEnd])
        ) AS WorkBlockPivot
    ) AS WorkBlockDurationsCTE

/* 8. Join days with no hours logged for each agent */
RIGHT JOIN
    (SELECT
        UNAME.Uname,
        UNAME.Unum,
        DaysCTE.Day
    FROM UNAME
    CROSS JOIN
        (SELECT
            CAST(date_id AS date) AS Day
        FROM CALENDAR
        /* Use days up to 7 days into the future */
        WHERE CAST(date_id AS date) <= DATEADD(DAY, 7, GETDATE())
        ) AS DaysCTE
    ) AS DayFillerCTE
    ON
        (DayFillerCTE.Unum = WorkBlockDurationsCTE.whoagentid
        AND DayFillerCTE.Day = WorkBlockDurationsCTE.EventDay)

WHERE
    DayFillerCTE.Day < @enddate
    AND DayFillerCTE.Day > @startdate

GROUP BY
    DayFillerCTE.Day,
    DayFillerCTE.Uname,
    WorkBlockDurationsCTE.whoagentid

ORDER BY
    DayFillerCTE.Uname,
    DayFillerCTE.Day
    
OFFSET 0 ROWS
