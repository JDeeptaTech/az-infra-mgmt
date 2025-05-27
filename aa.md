Subject: Summary of Current Pending Tasks – VRA & Storage

Hi All,

Please find below the list of pending tasks currently in progress. Most tasks require coordination during IST mornings, as the client team is primarily based in India. Kindly note, there may be unforeseen blockers that could impact timelines.

Storage (Target: 15-June-2025)
1. EV
Need to implement post-checks. Currently, URLs are available only for one environment. We need to integrate this into the process and obtain URLs for all other environments.

The scope currently includes only three regions: UK, US, and HK. Logic needs to be updated for single-region data center selection.

Cloud insights inventory is not available; must rely on a hardcoded list.

The process is tested in AAP Central, so additional time is needed to validate in CTO AAP.

Activities:

SSL: 2–3 days
Status: Testing and evidence collection pending.

Pathing: 6 days
Status: Testing and evidence collection pending.

Final step: Deployment to Production & CR creation.

2. IA SSL (Estimated: 5 Days)
Linux setup completed; working on equivalent steps for Windows.

Waiting for HSBC input to finalize IA setup for Windows. Documentation underway.

This is also tested in AAP Central; validation required in CTO AAP.

Activities:

Implement post-checks.

Deployment to Production & CR creation.

3. NBU (Minimum 8 Days)
Requires SME involvement for upgrade, downgrade, and re-upgrade testing.

VRA – Linux Build (Target: 20-June-2025)
Terraform
Develop cluster & single data source selection logic – 4 days

Test backup tag logic – 2 days

Jenkins CI pipeline setup – 5 days

Jenkins CD pipeline setup – 5 days

RTL validation – 5 days

API
Infra setup & deployment pipeline – 10 days

API integration with AAP & Hashi Vault – 2–3 days

Namespace integration with Harshi – TBD

Jenkins CI pipeline – 5 days

Jenkins CD pipeline – 5 days

AAP – RTL
Continue work on RTL process
