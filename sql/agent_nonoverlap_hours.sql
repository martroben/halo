/*
Dev notes:

# 2023-11-1

If the action has 0-time (same start and stop time), it screws up the cumulative sum.
Should filter out 0-time actions in the beginning.

Makes it better, but there's still a problem: when two actions begin at the same time, the cumulative sum is 2.
Can fix it by making the start condition as index > 0 and cumulative = 0.

Then there will be several begin conditions in a row.
Can try to aggregate subsequent begin conditions with the earliest date.
Use lag value of cumulative index - only valid start if it's 0.

Have to make sure that the time window doesn't start with ongoing time block.
Otherwise the cumulative index will start as -1.
Removing by assigning "overlap" for EventIndex:-1 | CumulativeIndex: 0 | CumulativeIndexLag: NULL events

Timeblock with no end action in the end might also be a problem.

After removing "overlap" events, there is not much sense using ticket and action numebers anymore
because there are random gaps.


# earlier

Original report uses timetaken field, but to use the overlap handling algorithm, should use ActionArrivalDate and ActionCompletionDate instead.
How to handle Actions that span from one day to another? Will just log to the day when the action completed (using ActionCompletionDate)

Overlap removal algorithm:
https://stackoverflow.com/questions/58128050/total-duration-time-without-overlapping-time-in-sql-server

Checked if timetaken + nonbilltime is the same as ActionCompletionDate - ActionArrivalDate. Seems to be.

Actions don't seem to have unique ID-s. Using a combination of Faultid and actionnumber. False - there is an id column, but a combination might still be better

Might be a good idea to use some user id, rather than who column? whoagentid maybe?


Calculate cumulative sum by Agent
https://stackoverflow.com/questions/17971988/sql-server-cumulative-sum-by-group


Only leave events that are start or end of a batch of actions
Calculate durations

Maybe also carry some billing multiplier from actions?
*/


SELECT
    DayFillerCTE.Uname AS Agent,
    DayFillerCTE.Day AS Date,
    SUM(WorkBlockDurationsCTE.DurationHours) AS HoursLogged
FROM
    (SELECT
        *,
        CAST(BlockEnd AS date) AS EventDay,
        CAST(ROUND(DATEDIFF(second, BlockStart, BlockEnd) / 3600.0, 2) AS Decimal(18,2)) AS DurationHours
    FROM
        (SELECT
            EventTime,
            who,
            whoagentid,
            WorkBlockEvent,
            /* Give same index to each two rows following each other to group same workblock events */
            (ROW_NUMBER() OVER(PARTITION BY whoagentid ORDER BY EventTime) - 1) / 2 AS AgentWorkBlockIndex
        FROM
            (SELECT
                *,
                CASE
                    WHEN EventIndex = 1 AND CumulativeIndex > 0 AND ISNULL(CumulativeIndexLag, 0) = 0 THEN 'BlockStart'
                    WHEN EventIndex = -1 AND CumulativeIndex = 0 AND ISNULL(CumulativeIndexLag, 0) <> 0 THEN 'BlockEnd'
                    ELSE 'overlap'
                END AS WorkBlockEvent
            FROM
                (SELECT
                    *,
                    LAG(CumulativeIndex) OVER (PARTITION BY whoagentid ORDER BY EventTime) CumulativeIndexLag
                FROM
                    (SELECT
                        *,
                        SUM(EventIndex)
                            OVER (PARTITION BY whoagentid ORDER BY EventTime) AS CumulativeIndex
                    FROM
                        (SELECT
                            *,
                            CASE
                                WHEN Event = 'ActionArrivalDate' THEN 1
                                WHEN Event = 'ActionCompletionDate' THEN -1
                                ELSE 0
                            END AS EventIndex
                        FROM
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
            ) AS WorkBlockCTE
        WHERE WorkBlockEvent <> 'overlap'
        ) AS WorkBlockIndicesCTE
    PIVOT
        (MAX(EventTime)
        FOR WorkBlockEvent IN ([BlockStart], [BlockEnd])
        ) AS WorkBlockPivot
    ) AS WorkBlockDurationsCTE

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
        /* Count days up to 7 days from today */
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
