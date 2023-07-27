/* dev notes
# 20824
Get total times allocated to different charge types for each ticket of a certain customer.
Times are rounded up to the nearest quarter hour.

#########################
# TABLES & COLUMNS USED #
#########################

FAULTS: Ticket info
	.Faultid: Ticket id
	.Symtom: Ticket summary
	.datecleared: Ticket closing datecleared
	.Areaint: Ticket customer id
	.userid: Technician id
	.sitenumber: Site id
	.FDeleted: True if ticket is deleted
AREA: Customer info
	.aareadesc: Customer name
	.Aarea: Customer id
SITE: Site info
	.sdesc: Site name
	.CFTransportSiteAndBackKM: Custom field, kilometers to site and back
	.Ssitenum: Site id
USERS: Technician info
	.uusername: Technician name
	.Uid: Technician id
ACTIONS: Ticket action info
	.ActionChargeHours: Hours associated with some charge type on action
	.ActionNonChargeHours: Hours not associated with a charge type on action
	.timetaken: Time logged on action
	.faultid: Action ticket id
	.actionapid: Appointment id if action is associated with an appointment
	.actioncode: Charge type. Values from LOOKUP table by fid = 17. such that LOOKUP.fcode = ACTIONS.actioncode + 1 (weird)
APPOINTMENT: Appointment info
	.APid: Appointment id
	.apappointmenttype: Appointment type code
LOOKUP: Info about custom field values
	.fvalue: Human readable value of custom field
	.fcode: Number coded value of custom field
	.fid: Custom field id


####################
# HARDCODED VALUES #
####################

AREA.Aarea = 121 - Tickets for a certain customer
LOOKUP.fid = 17 - Values for the charge type field
LOOKUP.fid = 63 - Values for the appointment type field


###################
# HELPFUL QUERIES #
###################

See actioncodes for all charge types and their corresponding lookup codes:
SELECT
    LOOKUP.fvalue,
    LOOKUP.fcode,
    UniqueActioncodes.actioncode
FROM LOOKUP
    LEFT JOIN (SELECT actioncode FROM ACTIONS GROUP BY actioncode) AS UniqueActioncodes
    ON LOOKUP.fcode =  UniqueActioncodes.actioncode + 1
WHERE LOOKUP.fid = 17

See names for APPOINTMENT.apappointmenttype values:
SELECT fcode, fvalue
FROM LOOKUP
WHERE FID = 63

Round up to nearest 0.25 (only works for positive numbers)
FLOOR(time) + CEILING((time - FLOOR(time)) * 4) / 4

*/


SELECT 
    FAULTS.Faultid AS [Ticket ID],
    AREA.aareadesc AS [Customer],
    SITE.sdesc AS [Site Name],
    USERS.uusername AS [User Name],
    FAULTS.Symptom AS [Title],
    FLOOR(SUM(ACTIONS.ActionChargeHours)) + 
		  CEILING((SUM(ACTIONS.ActionChargeHours) - FLOOR(SUM(ACTIONS.ActionChargeHours))) * 4) / 4 
      AS [Charge H],
    FLOOR(SUM(ACTIONS.ActionNonChargeHours)) + 
		  CEILING((SUM(ACTIONS.ActionNonChargeHours) - FLOOR(SUM(ACTIONS.ActionNonChargeHours))) * 4) / 4 
      AS [Contract H],
    ChargeTypes.fvalue AS [Charge Type],
    SITE.CFTransportSiteAndBackKM AS [KM to customer and back],
    FORMAT(MAX(FAULTS.datecleared), 'dd/MM/yyyy') AS [Date Closed],
	AppointmentTypes.fvalue AS [Site Visit],
	ROUND(SUM(ACTIONS.timetaken), 2) AS [Time Taken]
FROM FAULTS
    LEFT JOIN AREA ON FAULTS.Areaint = AREA.Aarea
    LEFT JOIN USERS ON FAULTS.userid = USERS.Uid
    LEFT JOIN SITE ON FAULTS.sitenumber = SITE.Ssitenum
    LEFT JOIN ACTIONS ON FAULTS.Faultid = ACTIONS.faultid
	LEFT JOIN APPOINTMENT ON ACTIONS.actionapid = APPOINTMENT.APid
	LEFT JOIN (SELECT fvalue, fcode FROM LOOKUP WHERE fid = 17)
		AS ChargeTypes
		ON ACTIONS.actioncode + 1 = ChargeTypes.fcode
	LEFT JOIN (SELECT fvalue, fcode FROM LOOKUP WHERE fid = 63 AND fcode = 2)
		AS AppointmentTypes
		ON APPOINTMENT.apappointmenttype = AppointmentTypes.fcode
WHERE AREA.Aarea = 121
	AND ISNULL(FAULTS.FDeleted, 0) = 0
    AND ISNULL(ACTIONS.timetaken, 0) <> 0
GROUP BY
    FAULTS.Faultid,
    AREA.aareadesc,
    SITE.sdesc,
    USERS.uusername,
    FAULTS.Symptom,
	ChargeTypes.fvalue,
    SITE.CFTransportSiteAndBackKM,
    AppointmentTypes.fvalue
ORDER BY [Ticket ID] DESC OFFSET 0 ROWS
