/* dev notes
# 26753
Report with total monthly opened and closed tickets by Agent
(Only Agents with default Team set)

##################
# RESULT COLUMNS #
##################

Year, Month         Result month
Agent               Agent name
Default Team        Agent's default Team
New tickets         Number of new tickets opened and assigned to Agent
Closed tickets      Number of tickets Closed that were assigned to Agent


#########################
# TABLES & COLUMNS USED #
#########################

FAULTS              Ticket info
.DateOccured        Date of opening the ticket
.DateCleared        Date of closing the ticket
.AssignedToInt      Agent id to whom the ticket is assigned

UNAME               Halo dashboard user info (Agents)
.UName              Agent name
.UNum               Agent id (not the same as USERS.Uid)
.usection           Agent default Team

UNAMESECTION        Teams that Agents belong to
.USunum             Agent id
.USSDID             Team id
.USsection          Team name

CALENDAR            Calendar database
.date_id            Date in 'YYYY/OM/DD' format
.date_day           Number of the day
.date_month         Month number
.date_year          Year number


#########################################
# CTE-s USED (Common Table Expressions) #
#########################################

AllMonthsCTE            List of consecutive months.
DefaultTeamsCTEs        List of Agents with default Team information.
MonthFillerCTE          Combination of AllMonthsCTE and DefaultTeamsCTE, to create zero value rows for months with no tickets.
EventsCTE               FAULTS table with separate rows for opening and closing each ticket.
AgentEventsCTE          Agents with a separate row for opening and closing each ticket.
AgentMonthEventsCTE     Agents with total number of opened and closed tickets aggregated by month.


####################
# HARDCODED VALUES #
####################

CALENDAR.date_id BETWEEN '2023/01/01' AND GETDATE()         Report starts from 2023/01/01
UNAMESECTION.USsection = UNAME.usection                     Show only Agents that have default Team set
AgentMonthEventsCTE.USSDID = 7                              Show only Agents from a certain Team

*/


SELECT
    AgentMonthEventsCTE.date_year AS [Year],
    AgentMonthEventsCTE.date_month AS [Month],
    AgentMonthEventsCTE.uname AS [Agent],
    AgentMonthEventsCTE.USsection AS [Default team],
    AgentMonthEventsCTE.DateOccured AS [New tickets],
    AgentMonthEventsCTE.DateCleared AS [Closed tickets]
FROM
    (SELECT
        MonthFillerCTE.date_year,
        MonthFillerCTE.date_month,
        MonthFillerCTE.Unum,
        MonthFillerCTE.uname,
        MonthFillerCTE.USSDID,
        MonthFillerCTE.USsection,
        EventsCTE.EventType
    FROM
        FAULTS UNPIVOT (EventDate FOR EventType IN (DateOccured, DateCleared)) AS EventsCTE
        RIGHT JOIN
            (SELECT
                AllMonthsCTE.date_year,
                AllMonthsCTE.date_month,
                DefaultTeamsCTE.Unum,
                DefaultTeamsCTE.uname,
                DefaultTeamsCTE.USSDID,
                DefaultTeamsCTE.USsection
            FROM
                (SELECT
                        CALENDAR.date_year,
                        CALENDAR.date_month
                    FROM CALENDAR
                    WHERE
                        CALENDAR.date_day = 1
                        AND CALENDAR.date_id BETWEEN '2023/01/01' AND GETDATE()
                                    /* Report start date ^ */
                ) AS AllMonthsCTE
                CROSS JOIN
                    (SELECT DISTINCT
                                UNAME.Unum,
                                UNAME.uname,
                                UNAMESECTION.USSDID,
                                UNAMESECTION.USsection
                            FROM
                                UNAMESECTION
                                LEFT JOIN UNAME
                                    ON UNAMESECTION.USunum = UNAME.Unum
                            WHERE
                                /* Select only Agents that have default Team set */
                                UNAMESECTION.USsection = UNAME.usection
                    ) AS DefaultTeamsCTE
            ) AS MonthFillerCTE
            ON
                MonthFillerCTE.Unum = EventsCTE.AssignedToInt
                AND MonthFillerCTE.date_year = YEAR(EventsCTE.EventDate)
                AND MonthFillerCTE.date_month = MONTH(EventsCTE.EventDate)) AS AgentEventsCTE
    PIVOT (COUNT(AgentEventsCTE.EventType) FOR AgentEventsCTE.EventType IN (DateOccured, DateCleared)) AS AgentMonthEventsCTE

/* Select only one team and one month
WHERE
    AgentMonthEventsCTE.USSDID = 7,
      /* Select only Agents from ^Project Managers Team*/
    AgentMonthEventsCTE.date_year = YEAR(GETDATE()),
    AgentMonthEventsCTE.date_month = MONTH(GETDATE())
*/
