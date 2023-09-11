/* dev notes
# 26299
Report to show Team's projects that are either open or closed within last 7 days.

#########################
# TABLES & COLUMNS USED #
#########################

FAULTS              Ticket info
.Faultid            Ticket id
.Areaint            Customer id
.DateOccured        Date of opening ticket
.DateCleared        Date of closing the ticket
.Symptom            Ticket description
.Status             Ticket status id
.RequestTypeNew     Ticket type id
.FOppTargetDate     Ticket (project) target date

AREA                Customer info
.AAreaDesc          Customer name
.Aarea              Customer id

UNAME               Halo dashboard user info (Agents)
.UName              User name

SECTIONDETAIL       Teams info
.SDid               Team id
.SDSectionName      Team name

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

FieldValuesCTE      Values of Default Team custom field


####################
# HARDCODED VALUES #
####################

FAULTS.Status <> 9              Projects with status that is not Closed
DATEADD(week, -1, GETDATE())    Tickets within last week (7 days)
FAULTS.RequestTypeNew IN (5)    Ticket types: 5 - Project
LOOKUP.fid = 146                CFDefaultTeam field values
UNAME.Unum = $agentid           Current Agent

*/


SELECT
    FAULTS.Faultid,
    AREA.AAreaDesc AS [Client],
    FieldValuesCTE.fvalue AS [Client default team],
    FAULTS.Symptom AS [Project name],
    FAULTS.FOppTargetDate AS [Target date],
    CASE
        WHEN FAULTS.Status = 9 AND FAULTS.DateCleared >= DATEADD(week, -1, GETDATE()) THEN 1
        ELSE 0
    END AS [Closed (last 7 days)]
FROM
    FAULTS
    LEFT JOIN AREA ON FAULTS.Areaint = AREA.Aarea
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
    LEFT JOIN SECTIONDETAIL
        ON FieldValuesCTE.fvalue = SECTIONDETAIL.SDSectionName
WHERE
    FAULTS.RequestTypeNew IN (5)
    AND (FAULTS.Status <> 9 OR FAULTS.DateCleared >= DATEADD(week, -1, GETDATE()))
    /* Show only current Agent team */
    AND SECTIONDETAIL.SDid = 
        (SELECT
            UNAMESECTION.USSDID
        FROM UNAME
            LEFT JOIN UNAMESECTION
            ON UNAMESECTION.USunum = UNAME.Unum
        WHERE UNAME.Unum = $agentid)

ORDER BY FAULTS.DateOccured OFFSET 0 ROWS
