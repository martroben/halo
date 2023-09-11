/* dev notes
# 26299
Report with various success metrics, aggregated by month and team custom field.

##################
# RESULT COLUMNS #
##################

Year, Month         Result month
Team                Team name

NPS                 Net Promoter Score
NPS Trend           Given month NPS difference from 6 previous months' average in standard deviations
NPS Percentile      Team NPS percentile rank among all teams on given month

Tickets             Number of tickets cleared during given month
Tickets Trend       Given month number of tickets difference from 6 previous months' average in standard deviations
Tickets Percentile  Team tickets cleared percentile rank among all teams on given month

Avg Clear Time      Team average ticket clearing time during given month
Clear Time Trend    Average clearing time difference from 6 previous months' average in standard deviations (positive if decreases)
Clear Time Percentile Team average clearing time percentile rank among all teams on given month


#########################
# TABLES & COLUMNS USED #
#########################

FAULTS: Ticket info
.Faultid            Ticket id
.DateCleared        Date of closing the ticket
.ClearTime          Time recorded on ticket
.Areaint            Ticket customer id

AREA                Customer info
.Aarea              Customer id
.CFDefaultTeam      Custom field for default team

FEEDBACK            Customer feedback results)
.FBFaultID          Ticket id
.FBScore            Feedback score

CALENDAR            Calendar database
.date_id            Date in 'YYYY/OM/DD' format
.date_day           Number of the day

UNAME               Halo dashboard user info (technicians)
.UName              User name
.UNum               User id (not the same as USERS.Uid)

UNAMESECTION        Teams that Agents belong to
.USunum             Agent id
.USSDID             Team id

LOOKUP              Info about custom field values
.fvalue             Human readable value of custom field
.fcode              Number coded value of custom field
.fid                Custom field id


#########################################
# CTE-s USED (Common Table Expressions) #
#########################################

AllMonthsCTE        List of consecutive months.
TeamInfoCTE         List of Teams, their names and their first cleared ticket months (WorkStart).
                    Necessary to calculate sliding average only over the time that the Team has actually been employed.
MonthFillerCTE      Combination of AllMonthsCTE and TeamInfoCTE, to create zero value rows for months with no tickets.
                    Necessary to get correct averages and standard deviations.
                    Also necessary because window functions work by number of preceeding rows, not by date column.
TeamByMonthCTE      Team survey results, ticket counts and average time resolution times by month.
RawDataCTE          Team NPS, ticket count and resolution time with percentile ranks, sliding averages and standard deviations.
                    Monthly, unrounded.


####################
# HARDCODED VALUES #
####################

ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING                    Window for sliding averages and std. dev is 6 preceeding months
CALENDAR.date_id BETWEEN '2023/01/01' AND GETDATE()         Report starts from 2023/01/01
CASE WHEN FEEDBACK.FBScore IN (..., ..., ...) THEN 1        Scores that are counted as positive, neutral and negative in NPS
FAULTS.RequestTypeNew IN (1, 29)                            Task and Incident tickets
LOOKUP.fid = 146                                            CFDefaultTeam field values
UNAME.Unum = $agentid                                       Current Agent


#########
# NOTES #
#########

-   Use Neutral2 if you don't want to count unanswered surveys as neutral in NPS.
-   Current sliding average is over 6 months, but can be changed in RawDataCTE.
-   Average clearing time is calculated only over Task and Incident (id 1 & 29) ticket types.
-   Start date is set to 2023/01/01, but can be changed in AllMonthsCTE.

*/


SELECT
    YEAR(RawDataCTE.Mnth) AS [Year],
    MONTH(RawDataCTE.Mnth) AS [Month],
    RawDataCTE.TeamName AS [Team],

    /* NPS */
    CAST(RawDataCTE.NPS AS decimal(5,2)) AS [NPS],
    CASE
        WHEN RawDataCTE.NPSSlidingStdev = 0 THEN NULL
        ELSE CAST((RawDataCTE.NPS - RawDataCTE.NPSSlidingAvg) / RawDataCTE.NPSSlidingStdev AS decimal(5,2))
    END AS [NPS Trend (st dev)],
    CAST(ROUND(100 * RawDataCTE.NPSPercentile, 0) AS decimal(5,0)) AS [NPS Percentile],

    /* Number of tickets */
    RawDataCTE.TicketCount AS [Tickets],
    CASE
        WHEN RawDataCTE.TicketCountSlidingStdev = 0 THEN NULL
        ELSE CAST((RawDataCTE.TicketCount - RawDataCTE.TicketCountSlidingAvg) / RawDataCTE.TicketCountSlidingStdev AS decimal(5,2))
    END AS [Tickets Trend (st dev)],
    CAST(ROUND(100 * RawDataCTE.TicketCountPercentile, 0) AS decimal(5,0)) AS [Tickets Percentile],

    /* Average time to clear a ticket */
    CAST(RawDataCTE.ClearTime AS decimal(5,2)) AS [Avg Clear Time (hour)],
    CASE
        WHEN RawDataCTE.ClearTimeSlidingStdev = 0 THEN NULL
        /* Give positive std. deviation when clear time reduces */
        ELSE CAST((RawDataCTE.ClearTimeSlidingAvg - RawDataCTE.ClearTime) / RawDataCTE.ClearTimeSlidingAvg AS decimal(5,2))
    END AS [Clear Time Trend (st dev)],
    CAST(ROUND(100 * RawDataCTE.ClearTimePercentile, 0) AS decimal(5,0)) AS [Clear Time Percentile]

FROM
    (SELECT
        MonthFillerCTE.CFDefaultTeam,
        MonthFillerCTE.TeamName,
        MonthFillerCTE.Mnth,

        /* NPS */
        /* Change to Neutral2 if needed */
        100.0 * (TeamByMonthCTE.Positive - TeamByMonthCTE.Negative) / (TeamByMonthCTE.Positive + TeamByMonthCTE.Negative + TeamByMonthCTE.Neutral) AS NPS,
        PERCENT_RANK() OVER(
            PARTITION BY MonthFillerCTE.Mnth
            ORDER BY 100.0 * (TeamByMonthCTE.Positive - TeamByMonthCTE.Negative) / (TeamByMonthCTE.Positive + TeamByMonthCTE.Negative + TeamByMonthCTE.Neutral)
        ) AS NPSPercentile,
        AVG(100.0 * (TeamByMonthCTE.Positive - TeamByMonthCTE.Negative) / (TeamByMonthCTE.Positive + TeamByMonthCTE.Negative + TeamByMonthCTE.Neutral)) OVER(
            PARTITION BY MonthFillerCTE.CFDefaultTeam
            ORDER BY MonthFillerCTE.Mnth
            /* 6 month sliding average */
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS NPSSlidingAvg,
        STDEV(100.0 * (TeamByMonthCTE.Positive - TeamByMonthCTE.Negative) / (TeamByMonthCTE.Positive + TeamByMonthCTE.Negative + TeamByMonthCTE.Neutral)) OVER(
            PARTITION BY MonthFillerCTE.CFDefaultTeam
            ORDER BY MonthFillerCTE.Mnth
            /* 6 month sliding average */
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS NPSSlidingStdev,

        /* Number of tickets */
        /* Fills in 0 if ticket count is null */
        ISNULL(TeamByMonthCTE.TicketCount, 0) AS TicketCount,
        PERCENT_RANK() OVER(
            PARTITION BY MonthFillerCTE.Mnth
            ORDER BY ISNULL(TeamByMonthCTE.TicketCount, 0)
        ) AS TicketCountPercentile,
        AVG(CAST(ISNULL(TeamByMonthCTE.TicketCount, 0) AS Float)) OVER(
            PARTITION BY MonthFillerCTE.CFDefaultTeam
            ORDER BY MonthFillerCTE.Mnth
            /* 6 month sliding average */
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS TicketCountSlidingAvg,
        STDEV(ISNULL(TeamByMonthCTE.TicketCount, 0)) OVER(
            PARTITION BY MonthFillerCTE.CFDefaultTeam
            ORDER BY MonthFillerCTE.Mnth
            /* 6 month sliding average */
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS TicketCountSlidingStdev,

        /* Average time to clear a ticket */
        /* Only Task and Incident ticket types */
        TeamByMonthCTE.ClearTime,
        CASE
            /* Exclude null and 0 values from percentile calculation */
            WHEN TeamByMonthCTE.ClearTime IS NULL THEN NULL
            ELSE PERCENT_RANK() OVER(
                PARTITION BY
                    CASE
                        WHEN TeamByMonthCTE.ClearTime IS NULL THEN '1900/1/1'
                        ELSE MonthFillerCTE.Mnth
                    END
                ORDER BY TeamByMonthCTE.ClearTime DESC)
            END
        AS ClearTimePercentile,
        AVG(TeamByMonthCTE.ClearTime) OVER(
            PARTITION BY MonthFillerCTE.CFDefaultTeam
            ORDER BY MonthFillerCTE.Mnth
            /* 6 month sliding average */
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS ClearTimeSlidingAvg,
        STDEV(TeamByMonthCTE.ClearTime) OVER(
            PARTITION BY MonthFillerCTE.CFDefaultTeam
            ORDER BY MonthFillerCTE.Mnth
            /* 6 month sliding average */
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS ClearTimeSlidingStdev

    FROM
        (SELECT
            TeamInfoCTE.CFDefaultTeam,
            TeamInfoCTE.TeamName,
            TeamInfoCTE.WorkStart,
            AllMonthsCTE.Mnth
        FROM
            (SELECT
                Area.CFDefaultTeam,
                FieldValuesCTE.fvalue AS TeamName,
                /* Round date to months */
                DATEADD(MONTH, DATEDIFF(MONTH, 0, MIN(FAULTS.DateCleared)), 0) AS WorkStart
            FROM
                FAULTS
                LEFT JOIN Area ON Area.Aarea = Faults.Areaint
                LEFT JOIN
                    (SELECT
                        fcode,
                        fvalue
                    FROM
                        LOOKUP
                    WHERE
                        LOOKUP.fid = 146
                    ) AS FieldValuesCTE
                    ON Area.CFDefaultTeam = FieldValuesCTE.fcode
            WHERE
                /* Some dates in Halo are from 1899 but they are not displayed, because SQL can handle dates starting from 1900 */
                YEAR(FAULTS.DateCleared) > 1900
                /* Give aggregate values (percentiles etc.) only over teams that have a name */
                AND FieldValuesCTE.fvalue IS NOT NULL
            GROUP BY
                Area.CFDefaultTeam,
                FieldValuesCTE.fvalue
            ) AS TeamInfoCTE
            CROSS JOIN (
                SELECT
                    CAST(CALENDAR.date_id AS Date) AS Mnth
                FROM CALENDAR
                WHERE
                    CALENDAR.date_day = 1 AND CALENDAR.date_id BETWEEN '2023/01/01' AND GETDATE()
                                                        /* Report start date ^ */
                ) AS AllMonthsCTE
        ) AS MonthFillerCTE
        LEFT JOIN
            (SELECT
                Area.CFDefaultTeam,
                /* Round date to months */
                DATEADD(MONTH, DATEDIFF(MONTH, 0, FAULTS.DateCleared), 0) AS Mnth,
                SUM(CASE WHEN FEEDBACK.FBScore IN (9, 10) THEN 1
                    ELSE 0 END) AS Positive,
                /* Neutral counts all tickets without feedback as neutral */
                SUM(CASE WHEN ISNULL(FEEDBACK.FBScore, 0) = 0 THEN 1
                    WHEN FEEDBACK.FBScore IN (7, 8) THEN 1
                    ELSE 0 END) AS Neutral,
                /* Neutral2 only uses counts tickets where there is feedback */
                SUM(CASE WHEN FEEDBACK.FBScore IN (7, 8) THEN 1
                    ELSE 0 END) AS Neutral2,
                SUM(CASE WHEN FEEDBACK.FBScore IN (1, 2, 3, 4, 5, 6) THEN 1
                    ELSE 0 END) AS Negative,
                COUNT(*) AS TicketCount,
                AVG(
                    /* Average only across Incident (id: 1) and Task (id: 29) tickets with non-zero clear time */
                    CASE WHEN FAULTS.ClearTime <> 0 AND FAULTS.RequestTypeNew IN (1, 29) THEN FAULTS.ClearTime
                    ELSE NULL END
                ) AS ClearTime
            FROM
                FAULTS
                LEFT JOIN Area ON Area.Aarea = Faults.Areaint
                LEFT JOIN Feedback ON FAULTS.Faultid = FEEDBACK.FBFaultID
            GROUP BY
                Area.CFDefaultTeam,
                /* Round date to months */
                DATEADD(MONTH, DATEDIFF(MONTH, 0, FAULTS.DateCleared), 0)
            ) AS TeamByMonthCTE
            ON
                MonthFillerCTE.Mnth = TeamByMonthCTE.Mnth
                AND MonthFillerCTE.CFDefaultTeam = TeamByMonthCTE.CFDefaultTeam
    WHERE
        MonthFillerCTE.Mnth >= CAST(MonthFillerCTE.WorkStart AS Date)
    ) AS RawDataCTE

/* Show only current Agent team */
WHERE
    RawDataCTE.CFDefaultTeam = 
        (SELECT
            UNAMESECTION.USSDID
        FROM UNAME
            LEFT JOIN UNAMESECTION
            ON UNAMESECTION.USunum = UNAME.Unum
        WHERE UNAME.Unum = $agentid)

ORDER BY [Team], [Year], [Month] OFFSET 0 ROWS
