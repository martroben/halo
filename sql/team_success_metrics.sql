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


SELECT
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
    DATEADD(MONTH, DATEDIFF(MONTH, 0, FAULTS.DateCleared), 0)