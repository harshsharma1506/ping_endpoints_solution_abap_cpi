# CPI Integration Health Monitor & Dashboard

A comprehensive SAP ABAP solution for proactive monitoring and diagnostic visualization of SAP Cloud Platform Integration (CPI) SOAP connectivity.

## Business Case
In modern enterprise landscapes, SAP CPI serves as the backbone for critical data exchanges. Any disruption in CPI connectivity directly impacts business operations, leading to delayed orders, incomplete financial records, and operational bottlenecks. Traditional monitoring often relies on manual checks or reactive incident reports. This solution provides a proactive mechanism to detect, alert, and visualize connectivity health, ensuring minimal downtime and high system reliability.

## Use Case
*   **Proactive Connectivity Checks:** Automatically verify the reachability and configuration of CPI endpoints at regular intervals.
*   **Real-time Alerting:** Notify support teams via email immediately when an interface transitions from a healthy to an error state.
*   **Integration Health Dashboard:** Provide a centralized view for administrators to assess the current status of all CPI interfaces, identify failing services, and observe health trends over time.
*   **Root Cause Analysis:** Use detailed status codes (CONFIG_ERROR vs. ASSIGNMENT_ERROR) to quickly pinpoint whether issues are related to technical configuration or logical assignments.

## Impact
*   **Operational Efficiency:** Eliminates the need for manual connectivity pings, saving significant administrative effort.
*   **Faster MTTR (Mean Time To Repair):** Immediate alerts and detailed error logging significantly reduce the time required to identify and resolve issues.
*   **Increased Visibility:** Transparent health reporting via the dashboard ensures stakeholders are informed about integration reliability.
*   **Zero-Footprint Persistence:** Leverages standard SAP Business Application Log (BAL) infrastructure, avoiding the need for custom database tables and simplifying transport management.

## Architecture
The solution is built entirely using standard SAP ABAP technologies to ensure compatibility and ease of maintenance:

*   **Discovery Engine:** Dynamically identifies CPI logical ports by querying `srt_cfg_cli_asgn` for endpoints containing `hana.ondemand.com`.
*   **Monitoring Core:** Utilizes `cl_srt_wsp_ws_admin_manager=>ping` to perform real-time connectivity tests.
*   **Persistence Layer:** Uses the **SAP Application Log (BAL)** (Object: `ZCPI_MON`, Subobject: `SOAP_CONN`) to store historical health data.
*   **Analytics Engine:** Processes historical BAL data in memory using optimized search algorithms to determine trends and last successful timestamps.
*   **UI Layer:** Provides a user-friendly selection screen and a high-performance **ALV Dashboard** (`CL_SALV_TABLE`) with visual status indicators (traffic lights).
*   **Notification Layer:** Integrated with **SAP Business Communication Services (BCS)** for automated email dispatching, with recipients managed via `TVARVC`.

## Implementation Details
The project involved a significant refactoring and consolidation of legacy monitoring tools into a unified report:

1.  **Unified Report (`Z_CPI_INTEGRATION_HEALTH`):** Consolidated the monitoring and dashboarding functionalities into a single executable, providing a streamlined user experience.
2.  **Optimized Data Processing:** Implemented a high-performance logic for trend calculation. By using `BINARY SEARCH` to locate records in the sorted history table and `LOOP AT ... FROM index` for processing, the dashboard remains responsive even with a large volume of historical logs.
3.  **Standardized Status Classification:**
    *   `OK`: Ping successful (HTTP 200).
    *   `CONFIG_ERROR`: Technical configuration issues (e.g., certificate problems, host resolution).
    *   `ASSIGNMENT_ERROR`: Issues with the logical port assignment to the consumer proxy.
4.  **Trend Indicators:**
    *   `↑`: Service has recovered since the last check.
    *   `↓`: Service has degraded or is repeatedly failing.
    *   `→`: Service status remains unchanged (Stable).
5.  **Dynamic Filtering:** Selection screen filters allow users to narrow down the dashboard view by Service Name, Logical Port, or specific Health Status.
