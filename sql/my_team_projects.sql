
SELECT
    FAULTS.Faultid,
    AREA.AAreaDesc,
    FAULTS.Symptom,
    CAST(FAULTS.FOppTargetDate AS Date) AS FOppTargetDate,
    CASE
        WHEN FAULTS.Status = 9 AND FAULTS.DateCleared >= DATEADD(week, -1, GETDATE()) THEN 'Closed in last 7 days'
        ELSE 'Open'
    END AS ProjectStatus
FROM
    FAULTS
    LEFT JOIN AREA ON FAULTS.Areaint = AREA.Aarea
WHERE
    FAULTS.RequestTypeNew IN (5)
    AND (FAULTS.Status <> 9 OR FAULTS.DateCleared >= DATEADD(week, -1, GETDATE()))
ORDER BY FAULTS.DateOccured OFFSET 0 ROWS


/*
Project ticket types that have had child tickets

5 	Project
33 	Development project
20  Project Task
36  Pre-sales
40  Business Application Development
43  Objective
44  Objective task
*/


/*
Columns of interest

fProjectInternalTask
CFProjectNotes
requesttypenew=5
FTemplateParentID
fChildCount
fxrefto
FixByDate
*/


/* Ticket types that are projects

SELECT RTid FROM requesttype WHERE RTIsProject = 1
*/