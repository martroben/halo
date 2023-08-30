SELECT
    YEAR(RawDataCTE.Mnth) AS [Year],
    MONTH(RawDataCTE.Mnth) AS [Month],
    RawDataCTE.Uname AS [Agent],

    /* NPS */
    CAST(RawDataCTE.NPS AS decimal(5,2)) AS [NPS Score],
    CASE
        WHEN RawDataCTE.NPSSlidingStdev = 0 THEN NULL
        ELSE CAST((RawDataCTE.NPS - RawDataCTE.NPSSlidingAvg) / RawDataCTE.NPSSlidingStdev AS decimal(5,2))
    END AS [NPS Trend (st dev)],
    CAST(100 * RawDataCTE.NPSPercentile AS decimal(5,2)) AS [NPS Percentile],

    /* Number of tickets */
    RawDataCTE.TicketCount AS [Tickets],
    CASE
        WHEN RawDataCTE.TicketCountSlidingStdev = 0 THEN NULL
        ELSE CAST((RawDataCTE.TicketCount - RawDataCTE.TicketCountSlidingAvg) / RawDataCTE.TicketCountSlidingStdev AS decimal(5,2))
    END AS [Tickets Trend (st dev)],
    CAST(100* RawDataCTE.TicketCountPercentile AS decimal(5,2)) AS [Tickets Percentile],

    /* Average time to clear a ticket */
    CAST(RawDataCTE.ClearTime AS decimal(5,2)) AS [Avg Clear Time (hour)],
    CASE
        WHEN RawDataCTE.ClearTimeSlidingStdev = 0 THEN NULL
        /* Give positive std. deviation when clear time reduces */
        ELSE CAST((RawDataCTE.ClearTimeSlidingAvg - RawDataCTE.ClearTime) / RawDataCTE.ClearTimeSlidingAvg AS decimal(5,2))
    END AS [Avg Clear Time Trend (st dev)],
    CAST(100* RawDataCTE.ClearTimePercentile AS decimal(5,2)) AS [Avg Clear Time Percentile]

FROM
    (SELECT
        MonthFillerCTE.ClearWhoInt,
        Uname.UName,
        MonthFillerCTE.Mnth,

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

        /* Only Task and Incident tickets */
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
                Faults.ClearWhoInt,
                /* Round date to months */
                DATEADD(MONTH, DATEDIFF(MONTH, 0, MIN(Faults.DateCleared)), 0) AS WorkStart
            FROM Faults
            /* Some dates in Halo are from 1899 but they are not displayed, because SQL can handle dates starting from 1900 */
            WHERE YEAR(Faults.DateCleared) > 1900
            GROUP BY Faults.ClearWhoInt
            ) AS AgentInfoCTE
            CROSS JOIN (
                SELECT
                    CAST(date_id AS Date) AS Mnth
                FROM CALENDAR
                /* Report start date */
                WHERE date_day = 1 AND date_id BETWEEN '2023/01/01' AND GETDATE()
                ) AS AllMonthsCTE
        ) AS MonthFillerCTE
        LEFT JOIN (
            SELECT
                Faults.ClearWhoInt AS AgentId,
                /* Round date to months */
                DATEADD(MONTH, DATEDIFF(MONTH, 0, Faults.DateCleared), 0) AS Mnth,
                SUM(CASE WHEN Feedback.FBScore IN (9, 10) THEN 1
                    ELSE 0 END) AS Positive,
                /* Neutral counts all tickets without feedback as neutral */
                SUM(CASE WHEN ISNULL(Feedback.FBScore, 0) = 0 THEN 1
                    WHEN Feedback.FBScore IN (7,8) THEN 1
                    ELSE 0 END) AS Neutral,
                /* Neutral2 only uses counts tickets where there is feedback */
                SUM(CASE WHEN Feedback.FBScore IN (7,8) THEN 1
                    ELSE 0 END) AS Neutral2,
                SUM(CASE WHEN Feedback.FBScore IN (1, 2, 3, 4, 5, 6) THEN 1
                    ELSE 0 END) AS Negative,
                COUNT(*) AS TicketCount,
                AVG(
                    /* Average only across Incident (id: 1) and Task (id: 29) tickets with non-zero clear time */
                    CASE WHEN Faults.ClearTime <> 0 AND Faults.RequestTypeNew IN (1, 29) THEN Faults.ClearTime
                    ELSE NULL END
                ) AS ClearTime
            FROM Faults
                LEFT JOIN Feedback ON Faults.Faultid = Feedback.FBFaultID
            GROUP BY
                Faults.ClearWhoInt,
                /* Round date to months */
                DATEADD(MONTH, DATEDIFF(MONTH, 0, Faults.DateCleared), 0)
            ) AS AgentByMonthCTE
            ON
                MonthFillerCTE.Mnth = AgentByMonthCTE.Mnth
                AND MonthFillerCTE.ClearWhoInt = AgentByMonthCTE.AgentId
        LEFT JOIN Uname ON MonthFillerCTE.ClearWhoInt = Uname.UNum
    WHERE
        MonthFillerCTE.Mnth >= CAST(MonthFillerCTE.WorkStart AS Date)
) AS RawDataCTE

ORDER BY [Agent], [Year], [Month] OFFSET 0 ROWS
