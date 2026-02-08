# API Integration Health Monitor & Dashboard

A comprehensive SAP ABAP solution for proactive monitoring and diagnostic visualization of SAP SOAP connectivity.

## Business Case
In modern enterprise landscapes, SAP SOAP serves as the backbone for critical data exchanges. Any disruption in connectivity directly impacts business operations, leading to delayed orders, incomplete financial records, and operational bottlenecks. Traditional monitoring often relies on manual checks or reactive incident reports. This solution provides a proactive mechanism to detect, alert, and visualize connectivity health, ensuring minimal downtime and high system reliability.

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
*   **Persistence Layer:** Uses the **SAP Application Log (BAL)** (Object: `ZAPI_MON`, Subobject: `SOAP_CONN`) to store historical health data.
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

## Some censored snapshots 😉

### Selection screen 
<img width="638" height="175" alt="{18A6C6D0-B5ED-4EF4-9E63-EA73A93F1095}" src="https://github.com/user-attachments/assets/a0c8c68e-8d17-48c6-b61a-461b4d6fb0f9" />

### SLG1 logs if ping fails during monitoring
<img width="910" height="277" alt="{9156F470-3EA4-416B-BAF1-D37358ADADA6}" src="https://github.com/user-attachments/assets/6c82e1de-4b83-448b-a6b3-2b26c765bd56" />

### Mail sent for the failed services by reading the BAL logs 
<img width="682" height="170" alt="{3CE15ED8-352C-4FE0-A742-63BB333B6870}" src="https://github.com/user-attachments/assets/d1addb06-8098-4858-b1ed-23c58952cc6b" />

### ALV report for seeing trend and diagnose
<img width="905" height="153" alt="{C4059B0C-961C-449B-9CB6-73B6E2B17CB4}" src="https://github.com/user-attachments/assets/70f88371-8374-4fc7-b2fd-8fad0344068a" />



