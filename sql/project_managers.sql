/*

Plan:
Pivot Faults to have a row for date occuring and date clearing
Join with calendar to add month row
Join with project managers to select only project managers

Notes:
team 7 - project managers
Use Faults.AssignedToInt not FAULTS.userid

*/


SELECT
    AllMonthsCTE.date_id,
    ProjectManagersCTE.uname
FROM
    (SELECT
        CALENDAR.date_id
    FROM CALENDAR
    WHERE
        CALENDAR.date_day = 1 AND CALENDAR.date_id BETWEEN '2023/01/01' AND GETDATE()
                                            /* Report start date ^ */
    ) AS AllMonthsCTE
    CROSS JOIN
        (SELECT
            UNAME.Unum,
            UNAME.uname
        FROM
            UNAMESECTION
            LEFT JOIN UNAME
                ON UNAMESECTION.USunum = UNAME.Unum
        WHERE
            /* Select only Agent default teams */
            UNAMESECTION.USsection = UNAME.usection
            /* Select Project Managers */
            AND UNAMESECTION.USSDID = 7
        ) AS ProjectManagersCTE
    LEFT JOIN
        FAULTS
            ON ProjectManagersCTE.Unum = FAULTS.userid AND 


SELECT
    AllMonthsCTE.date_id,
    FaultOccured.DateOccured,
    FaultOccured.Faultid
FROM
    (SELECT
        CALENDAR.date_id
    FROM CALENDAR
    WHERE
        CALENDAR.date_day = 1 AND CALENDAR.date_id BETWEEN '2023/01/01' AND GETDATE()
                                            /* Report start date ^ */
    ) AS AllMonthsCTE
    LEFT JOIN FAULTS AS FaultOccured
        ON datefromparts(YEAR(FaultOccured.DateOccured), MONTH(FaultOccured.DateOccured), 1) = AllMonthsCTE.date_id


SELECT
    Faultid,
    Symptom,
    EventDate,
    CASE
        WHEN EventType = 'DateOccured' THEN 1
        ELSE 0
    END AS Occured,
    CASE
        WHEN EventType = 'DateCleared' THEN 1
        ELSE 0
    END AS Cleared
FROM
    FAULTS
    UNPIVOT (EventDate FOR EventType IN (DateOccured, DateCleared)) AS Unpivoted