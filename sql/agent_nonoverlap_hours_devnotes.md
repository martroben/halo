# 2023-11-2
Apparently the phrase 'drop' can't be used in a Halo query.


# 2023-11-1
If the action has 0-time (same start and stop time), it screws up the cumulative sum.
Should filter out 0-time actions in the beginning.

Makes it better, but there's still a problem: when two actions begin at the same time, the cumulative sum is 2.
Can fix it by making the start condition as index > 0 and cumulative = 0.

Then there will be several begin conditions in a row.
Can try to aggregate subsequent begin conditions with the earliest date.
Use lag value of cumulative index - only valid start if it's 0.

Have to make sure that the time window doesn't start with ongoing time block.
Otherwise the cumulative index will start as -1.
Removing by assigning "overlap" for EventIndex:-1 | CumulativeIndex: 0 | CumulativeIndexLag: NULL events

Timeblock with no end action in the end might also be a problem.

After removing "overlap" events, there is not much sense using ticket and action numebers anymore
because there are random gaps.


# earlier
Original report uses timetaken field, but to use the overlap handling algorithm, should use ActionArrivalDate and ActionCompletionDate instead.
How to handle Actions that span from one day to another? Will just log to the day when the action completed (using ActionCompletionDate)

Overlap removal algorithm:
https://stackoverflow.com/questions/58128050/total-duration-time-without-overlapping-time-in-sql-server

Checked if timetaken + nonbilltime is the same as ActionCompletionDate - ActionArrivalDate. Seems to be.

Actions don't seem to have unique ID-s. Using a combination of Faultid and actionnumber. False - there is an id column, but a combination might still be better

Might be a good idea to use some user id, rather than who column? whoagentid maybe?


Calculate cumulative sum by Agent
https://stackoverflow.com/questions/17971988/sql-server-cumulative-sum-by-group


Only leave events that are start or end of a batch of actions
Calculate durations

Maybe also carry some billing multiplier from actions?