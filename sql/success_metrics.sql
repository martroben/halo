/* dev notes
# 26299
Report with various success metrics, aggregated by month and Agent.

##################
# RESULT COLUMNS #
##################

Year, Month         Result month
Agent               Agent name

NPS                 Net Promoter Score
NPS Trend           Given month NPS difference from 6 previous months' average in standard deviations
NPS Percentile      Agent NPS percentile rank among all agents on given month

Tickets             Number of tickets cleared during given month
Tickets Trend       Given month number of tickets difference from 6 previous months' average in standard deviations
Tickets Percentile  Agent tickets cleared percentile rank among all agents on given month

Avg Clear Time      Agent average ticket clearing time during given month
Clear Time Trend    Average clearing time difference from 6 previous months' average in standard deviations (positive if decreases)
Clear Time Percentile Agent average clearing time percentile rank among all agents on given month


#########################
# TABLES & COLUMNS USED #
#########################

FAULTS              Ticket info
.Faultid            Ticket id
.ClearWhoInt        Agent who closed the ticket
.DateCleared        Date of closing the ticket
.ClearTime          Time recorded on ticket

FEEDBACK            Customer feedback results)
.FBFaultID          Ticket id
.FBScore            Feedback score

CALENDAR            Calendar database
.date_id            Date in 'YYYY/OM/DD' format
.date_day           Number of the day

UNAME               Halo dashboard user info (technicians)
.UName              User name
.UNum               User id (not the same as USERS.Uid)


#########################################
# CTE-s USED (Common Table Expressions) #
#########################################

AllMonthsCTE        List of consecutive months.
AgentInfoCTE        List of Agents and their first cleared ticket months (WorkStart).
                    Necessary to calculate sliding average only over the time that Agent has actually been employed.
MonthFillerCTE      Combination of AllMonthsCTE and AgentInfoCTE, to create zero value rows for months with no tickets.
                    Necessary to get correct averages and standard deviations.
                    Also necessary because window functions work by number of preceeding rows, not by date column.
AgentByMonthCTE     Agent survey results, ticket counts and average time resolution times by month.
RawDataCTE          Agent NPS, ticket count and resolution time with percentile ranks, sliding averages and standard deviations.
                    Monthly, unrounded.


####################
# HARDCODED VALUES #
####################

ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING                    Window for sliding averages and std. dev is 6 preceeding months
CALENDAR.date_id BETWEEN '2023/01/01' AND GETDATE()         Report starts from 2023/01/01
CASE WHEN FEEDBACK.FBScore IN (..., ..., ...) THEN 1        Scores that are counted as positive, neutral and negative in NPS
FAULTS.RequestTypeNew IN (1, 29)                            Task and Incident tickets


#########
# NOTES #
#########

-   Use Neutral2 if you don't want to count unanswered surveys as neutral in NPS.
-   Current sliding average is over 6 months, but can be changed in RawDataCTE.
-   Average clearing time is calculated only over Task and Incident (id 1 & 29) ticket types.
-   Start date is set to 2023/01/01, but can be changed in AllMonthsCTE.
-   Uncomment the last WHERE line to show only results for the Agent that's looking.

*/


SELECT
    YEAR(RawDataCTE.Mnth) AS [Year],
    MONTH(RawDataCTE.Mnth) AS [Month],
    RawDataCTE.UName AS [Agent],

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
        MonthFillerCTE.ClearWhoInt,
        UNAME.UName,
        MonthFillerCTE.Mnth,

        /* NPS */
        /* Change to Neutral2 if needed */
        100.0 * (AgentByMonthCTE.Positive - AgentByMonthCTE.Negative) / (AgentByMonthCTE.Positive + AgentByMonthCTE.Negative + AgentByMonthCTE.Neutral) AS NPS,
        PERCENT_RANK() OVER(
            PARTITION BY MonthFillerCTE.Mnth
            ORDER BY 100.0 * (AgentByMonthCTE.Positive - AgentByMonthCTE.Negative) / (AgentByMonthCTE.Positive + AgentByMonthCTE.Negative + AgentByMonthCTE.Neutral)
        ) AS NPSPercentile,
        AVG(100.0 * (AgentByMonthCTE.Positive - AgentByMonthCTE.Negative) / (AgentByMonthCTE.Positive + AgentByMonthCTE.Negative + AgentByMonthCTE.Neutral)) OVER(
            PARTITION BY MonthFillerCTE.ClearWhoInt
            ORDER BY MonthFillerCTE.Mnth
            /* 6 month sliding average */
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS NPSSlidingAvg,
        STDEV(100.0 * (AgentByMonthCTE.Positive - AgentByMonthCTE.Negative) / (AgentByMonthCTE.Positive + AgentByMonthCTE.Negative + AgentByMonthCTE.Neutral)) OVER(
            PARTITION BY MonthFillerCTE.ClearWhoInt
            ORDER BY MonthFillerCTE.Mnth
            /* 6 month sliding average */
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS NPSSlidingStdev,

        /* Number of tickets */
        /* Fills in 0 if ticket count is null */
        ISNULL(AgentByMonthCTE.TicketCount, 0) AS TicketCount,
        PERCENT_RANK() OVER(
            PARTITION BY MonthFillerCTE.Mnth
            ORDER BY ISNULL(AgentByMonthCTE.TicketCount, 0)
        ) AS TicketCountPercentile,
        AVG(CAST(ISNULL(AgentByMonthCTE.TicketCount, 0) AS Float)) OVER(
            PARTITION BY MonthFillerCTE.ClearWhoInt
            ORDER BY MonthFillerCTE.Mnth
            /* 6 month sliding average */
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS TicketCountSlidingAvg,
        STDEV(ISNULL(AgentByMonthCTE.TicketCount, 0)) OVER(
            PARTITION BY MonthFillerCTE.ClearWhoInt
            ORDER BY MonthFillerCTE.Mnth
            /* 6 month sliding average */
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS TicketCountSlidingStdev,

        /* Average time to clear a ticket */
        /* Only Task and Incident ticket types */
        AgentByMonthCTE.ClearTime,
        CASE
            /* Exclude null and 0 values from percentile calculation */
            WHEN AgentByMonthCTE.ClearTime IS NULL THEN NULL
            ELSE PERCENT_RANK() OVER(
                PARTITION BY
                    CASE
                        WHEN AgentByMonthCTE.ClearTime IS NULL THEN '1900/1/1'
                        ELSE MonthFillerCTE.Mnth
                    END
                ORDER BY AgentByMonthCTE.ClearTime DESC)
            END
        AS ClearTimePercentile,
        AVG(AgentByMonthCTE.ClearTime) OVER(
            PARTITION BY MonthFillerCTE.ClearWhoInt
            ORDER BY MonthFillerCTE.Mnth
            /* 6 month sliding average */
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS ClearTimeSlidingAvg,
        STDEV(AgentByMonthCTE.ClearTime) OVER(
            PARTITION BY MonthFillerCTE.ClearWhoInt
            ORDER BY MonthFillerCTE.Mnth
            /* 6 month sliding average */
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS ClearTimeSlidingStdev

    FROM
        (SELECT
            AgentInfoCTE.ClearWhoInt,
            AgentInfoCTE.WorkStart,
            AllMonthsCTE.Mnth
        FROM
            (SELECT
                FAULTS.ClearWhoInt,
                /* Round date to months */
                DATEADD(MONTH, DATEDIFF(MONTH, 0, MIN(FAULTS.DateCleared)), 0) AS WorkStart
            FROM FAULTS
            /* Some dates in Halo are from 1899 but they are not displayed, because SQL can handle dates starting from 1900 */
            WHERE YEAR(FAULTS.DateCleared) > 1900
            GROUP BY FAULTS.ClearWhoInt
            ) AS AgentInfoCTE
            CROSS JOIN (
                SELECT
                    CAST(CALENDAR.date_id AS Date) AS Mnth
                FROM CALENDAR
                /* Report start date */
                WHERE CALENDAR.date_day = 1 AND CALENDAR.date_id BETWEEN '2023/01/01' AND GETDATE()
                ) AS AllMonthsCTE
        ) AS MonthFillerCTE
        LEFT JOIN (
            SELECT
                FAULTS.ClearWhoInt AS AgentId,
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
            FROM FAULTS
                LEFT JOIN Feedback ON FAULTS.Faultid = FEEDBACK.FBFaultID
            GROUP BY
                FAULTS.ClearWhoInt,
                /* Round date to months */
                DATEADD(MONTH, DATEDIFF(MONTH, 0, FAULTS.DateCleared), 0)
            ) AS AgentByMonthCTE
            ON
                MonthFillerCTE.Mnth = AgentByMonthCTE.Mnth
                AND MonthFillerCTE.ClearWhoInt = AgentByMonthCTE.AgentId
        LEFT JOIN
            Uname
            ON MonthFillerCTE.ClearWhoInt = UNAME.UNum
    WHERE
        MonthFillerCTE.Mnth >= CAST(MonthFillerCTE.WorkStart AS Date)
    ) AS RawDataCTE

/* WHERE RawDataCTE.ClearWhoInt = $agentid */
ORDER BY [Agent], [Year], [Month] OFFSET 0 ROWS