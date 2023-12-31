/* See actioncodes for all charge types and their corresponding lookup codes */
SELECT
    LOOKUP.fvalue,
    LOOKUP.fcode,
    UniqueActioncodes.actioncode
FROM LOOKUP
    LEFT JOIN (SELECT actioncode FROM ACTIONS GROUP BY actioncode) AS UniqueActioncodes
    ON LOOKUP.fcode =  UniqueActioncodes.actioncode + 1
WHERE LOOKUP.fid = 17


/* See names for APPOINTMENT.apappointmenttype values */
SELECT fcode, fvalue
FROM LOOKUP
WHERE FID = 63


/* Round up to nearest 0.25 (only works for positive numbers) */
FLOOR(time) + CEILING((time - FLOOR(time)) * 4) / 4


/* See names and steps of all existing workflows */
SELECT
	FLOWDETAIL.FDFHID AS [workflow id],
	FLOWHEADER.FHName AS [workflow name],
	FLOWDETAIL.FDSEQ AS [flow step number],
	FLOWDETAIL.FDName AS [flow step name],
	FLOWHEADER.fhactive AS [flow active]
FROM FLOWDETAIL
	LEFT JOIN FLOWHEADER ON FLOWHEADER.FHID = FLOWDETAIL.FDFHID


/* See what Custom Field names and values correspond to different lookup id-s */
SELECT
	FILookup AS [field lookup code],
	FIName AS [field code name],
	FILabel AS [field description]
FROM FIELDINFO
WHERE FILookup NOT IN (0, -1)


/* See all existing ticket status id-s */
SELECT
	Tstatus [status id],
	tstatusdesc [status description],
	TstatusSeq [status placement],
	tshortname [status code name]
FROM TSTATUS


/* See ticket type code (FAULTS.RequestTypeNew) meanings */
SELECT
    RTid,
    rtdesc
FROM
    RequestType
ORDER BY RTid OFFSET 0 ROWS


/* See all ticket types that are Projects */
SELECT RTid FROM requesttype WHERE RTIsProject = 1


/* See teams of all technicians */
SELECT
    UNAME.Unum,
    UNAME.uname,
    UNAMESECTION.USSDID,
    UNAMESECTION.USsection,
    UNAMESECTION.USinsection,           /* Can be assigned Team's tickets */
    UNAMESECTION.USunassignedaccess,    /* Can see Team's unassigned tickets */
    UNAMESECTION.USotheragentaccess,    /* Can see other Teammember's tickets */
    UNAMESECTION.usIsManager,
    CASE
        WHEN UNAMESECTION.USsection = UNAME.usection THEN 1
        ELSE 0
    END AS IsDefaultTeam
FROM
    UNAMESECTION
    LEFT JOIN UNAME
        ON UNAMESECTION.USunum = UNAME.Unum
ORDER BY UNAME.Unum OFFSET 0 ROWS


/* See default teams of all Agents */
SELECT
    UNAME.Unum,
    UNAME.uname,
    DefaultTeamsCTE.DefaultTeamId,
    DefaultTeamsCTE.DefaultTeam
FROM UNAME
    LEFT JOIN
    (SELECT DISTINCT
        UNAME.Unum,
        UNAME.uname,
        CASE
            WHEN UNAME.usection = UNAMESECTION.USsection THEN UNAME.usection
            ELSE NULL
        END AS DefaultTeam,
        CASE
            WHEN UNAME.usection = UNAMESECTION.USsection THEN UNAMESECTION.USSDID
            ELSE NULL
        END AS DefaultTeamId
    FROM
        UNAMESECTION
        LEFT JOIN UNAME
            ON UNAMESECTION.USunum = UNAME.Unum
    WHERE UNAME.usection = UNAMESECTION.USsection
    ) AS DefaultTeamsCTE
    ON UNAME.Unum = DefaultTeamsCTE.Unum