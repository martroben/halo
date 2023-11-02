# SQL queries for Halo
Using SQL in Halo has some limitations (can't assign variables etc.), therefore the queries are somewhat non-standard.


- [agent_monthly_tickets](agent_monthly_tickets.sql) - Monthly opened and closed tickets by Agent
- [agent_nonoverlap_hours](agent_nonoverlap_hours.sql) - Report of agent worked hours per day in a way that the overlapping hours are not double-counted. ([devnotes](agent_nonoverlap_hours_devnotes.md))
- [charge_type_totals](charge_type_totals.sql) - Get total times allocated to different charge types for each Ticket of a certain Client
- [helpful_queries](helpful_queries.sql) - Helpful views and queries
- [my_team_projects](my_team_projects.sql) - Projects by Team that are either open or have been closed within last 7 days
- [success_metrics](success_metrics.sql) - Various success metrics, aggregated by month and Agent
- [team_success_metrics](team_success_metrics.sql) - Various success metrics, aggregated by month and Client default Team (custom field)
- [tickets_in_project_stage](tickets_in_project_stage.sql) - See all tickets that are in a certain workflow stage

See individual scripts for additional info.
