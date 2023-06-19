/* dev notes
# 7675

#########################
# TABLES & COLUMNS USED #
#########################

FAULTS: Ticket info
	.Faultid: Ticket id
	.Symptom: Ticket summary
	.dateoccured: Ticket creation date
	.CFPipeline: Value of custom field "Pipeline"
	.Assignedtoint: Agent id that the ticket is assigned to
	.Status: Ticket status id
	.Areaint: Ticket customer id
	.FDeleted: True if ticket is deleted
AREA: Customer info
	.aareadesc: Customer name
	.Aarea: Customer id
UNAME: Agent info
	.uname: Agent name
	.Unum: Agent id
TSTATUS: Ticket statuses info
	.tstatusdesc: Status name
	.Tstatus: Status id
WorkflowHistory: Info about (latest) moves in workflow stages
	.whmoveddate: Datetime of move
	.whflowid: Workflow id
	.whmovedto: Stage id that workflow moved to
	.whfaultid: Ticket id where the workflow move occored in
LOOKUP: Info about custom field values
	.fvalue: Human readable value of custom field
	.fcode: Number coded value of custom field
	.fid: Custom field id


####################
# HARDCODED VALUES #
####################

WorkflowHistory.whflowid = 11 - Workflow type is "Deal workflow"
WorkflowHistory.whmovedto = 5 - Workflow step is "Project creation"
LOOKUP.fid = 137 - Custom field "Pipeline"
TSTATUS.Tstatus = 26 - ticket status is "Notify Projects".
ISNULL(FAULTS.FDeleted, 0) = 0 - Ticket not deleted (FDeleted either NULL or False)


###################
# HELPFUL QUERIES #
###################

See names and steps of all existing workflow:
SELECT
	FLOWDETAIL.FDFHID AS [workflow id],
	FLOWHEADER.FHName AS [workflow name],
	FLOWDETAIL.FDSEQ AS [flow step number],
	FLOWDETAIL.FDName AS [flow step name],
	FLOWHEADER.fhactive AS [flow active]
FROM FLOWDETAIL
	LEFT JOIN FLOWHEADER ON FLOWHEADER.FHID = FLOWDETAIL.FDFHID

See what Custom Field names and values correspond to different lookup id-s:
SELECT
	FILookup,
	FIName,
	FILabel
FROM FIELDINFO
WHERE FILookup NOT IN (0, -1)

See all existing ticket status id-s:
SELECT
	Tstatus,
	tstatusdesc,
	TstatusSeq,
	tshortname
FROM TSTATUS

*/


SELECT 
    FAULTS.Faultid AS [Ticket ID],
    AREA.aareadesc as [Customer],
    FAULTS.Symptom AS [Summary],
    UNAME.uname AS [Agent Name],
    TSTATUS.tstatusdesc AS [Status],
    FORMAT(FAULTS.dateoccured, 'dd/MM/yyyy')
        AS [Date Created],
    (SELECT FORMAT(MAX(whmoveddate), 'dd/MM/yyyy')
        FROM WorkflowHistory
        WHERE 
            whflowid = 11
            AND whmovedto = 5
            AND whfaultid = FAULTS.Faultid
        GROUP BY whfaultid)
        AS [Sent To Projects (Latest)],
    (SELECT fvalue
        FROM LOOKUP
        WHERE fcode = FAULTS.CFPipeline AND fid = 137)
        AS [Pipeline]
FROM FAULTS
    LEFT JOIN UNAME ON FAULTS.Assignedtoint = UNAME.Unum
    LEFT JOIN TSTATUS ON FAULTS.Status = TSTATUS.Tstatus
    LEFT JOIN AREA ON AREA.Aarea = FAULTS.Areaint
WHERE (ISNULL(FAULTS.FDeleted, 0) = 0)
    AND TSTATUS.Tstatus = 26
