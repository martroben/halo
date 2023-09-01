/* Get default team values for ticket */
SELECT
    Faults.Faultid,
    Faults.Areaint,
    Faults.DateCleared,
    Faults.ClearWhoInt,
    Area.AAreaDesc,
    Area.CFDefaultTeam,
    FieldValuesCTE.fvalue AS DefaultTeam
FROM FAULTS
LEFT JOIN Area ON Area.AArea = Faults.Areaint
LEFT JOIN (SELECT fcode, fvalue FROM LOOKUP WHERE LOOKUP.fid = 146) AS FieldValuesCTE ON Area.CFDefaultTeam = FieldValuesCTE.fcode
WHERE Faults.ClearWhoInt = 31

/*
CHANGES
TeamByMonthCTE 
TeamInfoCTE
*/


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
FROM FAULTS
    LEFT JOIN Area ON Area.AArea = Faults.Areaint
    LEFT JOIN Feedback ON FAULTS.Faultid = FEEDBACK.FBFaultID
GROUP BY
    Area.CFDefaultTeam,
    /* Round date to months */
    DATEADD(MONTH, DATEDIFF(MONTH, 0, FAULTS.DateCleared), 0)) AS TeamByMonthCTE







SELECT
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
            LEFT JOIN Area ON Area.AArea = Faults.Areaint
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
            /* Report start date */
            WHERE
                CALENDAR.date_day = 1 AND CALENDAR.date_id BETWEEN '2023/01/01' AND GETDATE()
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
            LEFT JOIN Area ON Area.AArea = Faults.Areaint
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
ORDER BY CFDefaultTeam, Mnth OFFSET 0 ROWS