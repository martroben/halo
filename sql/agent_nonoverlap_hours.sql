/*
# Dev notes:
Original report uses timetaken field, but to use the overlap handling algorithm, should use ActionArrivalDate and ActionCompletionDate instead.
How to handle Actions that span from one day to another? Will just log to the day when the action completed (using ActionCompletionDate)

Checked if timetaken + nonbilltime is the same as ActionCompletionDate - ActionArrivalDate. Seems to be.

Actions don't seem to have unique ID-s. Using a combination of Faultid and actionnumber. False - there is an id column, but a combination might still be better

Might be a good idea to use some user id, rather than who column? whoagentid maybe?


Calculate cumulative sum by Agent
Only leave events that are start or end of a batch of actions
Calculate durations
*/

SELECT
    ActionDatesUnpivotedCTE.Faultid,
    ActionDatesUnpivotedCTE.actionnumber,
    ActionDatesUnpivotedCTE.who,
    ActionDatesUnpivotedCTE.whoagentid,
    CASE
        WHEN ActionDatesUnpivotedCTE.Event = 'ActionArrivalDate' THEN 1
        WHEN ActionDatesUnpivotedCTE.Event = 'ActionCompletionDate' THEN -1
        ELSE 0
    END AS EventIndex,
    ActionDatesUnpivotedCTE.EventTime
FROM
    (SELECT
        ACTIONS.Faultid,
        ACTIONS.actionnumber,
        ACTIONS.who,
        ACTIONS.whoagentid,
        ACTIONS.ActionArrivalDate,
        ACTIONS.ActionCompletionDate,
        ACTIONS.ActionChargeHours,
        ACTIONS.ActionNonChargeHours
    FROM
        ACTIONS
    ) AS ActonDatesCTE
UNPIVOT
    (EventTime FOR Event IN (ActionArrivalDate, ActionCompletionDate)) AS ActionDatesUnpivotedCTE




/* all actions of one agent with necessary fields */
SELECT
        Faultid,
        actionnumber,
        who,
        whoagentid,
        ActionArrivalDate,
        ActionCompletionDate,
        ActionChargeHours,
        ActionNonChargeHours
    FROM
        ACTIONS
    WHERE
        Whe_ < @enddate
        AND Whe_ > @startdate
        AND who = 'asdasd'


/*
Simplified version of Halo report
*/
select
    who as Technician,
    round(sum(timetaken),2) as BillableHours,
    round(sum(nonbilltime),2) as NonBillableHours,
    round((sum(timetaken) + sum(nonbilltime)),2) as TotalHours
from
    ACTIONS
where
    whe_ < @enddate
    and whe_ > @startdate
group by who


/*
https://stackoverflow.com/questions/58128050/total-duration-time-without-overlapping-time-in-sql-server
*/