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
