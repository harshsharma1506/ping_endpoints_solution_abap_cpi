*&---------------------------------------------------------------------*
*& Report Z_CPI_INTEGRATION_HEALTH
*&---------------------------------------------------------------------*
REPORT z_cpi_integration_health.

TYPES: ty_status_text TYPE c LENGTH 128.
DATA: it_srt TYPE TABLE OF srt_cfg_cli_asgn WITH HEADER LINE.
*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE text-t01.
PARAMETERS: rb_mon  RADIOBUTTON GROUP g1 DEFAULT 'X' USER-COMMAND mode,
            rb_dash RADIOBUTTON GROUP g1.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE text-t02.
SELECT-OPTIONS: s_serv FOR it_srt-proxy_class,
                s_lp   FOR it_srt-lp_name.
DATA: gv_stat_dummy TYPE ty_status_text.
SELECT-OPTIONS: s_stat FOR gv_stat_dummy.
SELECTION-SCREEN END OF BLOCK b2.

*----------------------------------------------------------------------*
* CLASS lcl_integration_health DEFINITION
*----------------------------------------------------------------------*
CLASS lcl_integration_health DEFINITION.
  PUBLIC SECTION.
    METHODS: run.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_port,
             lp_name      TYPE srt_cfg_cli_asgn-lp_name,
             service_name TYPE srt_cfg_cli_asgn-proxy_class,
             protocol     TYPE srt_cfg_cli_asgn-protocol,
             host         TYPE srt_cfg_cli_asgn-host,
             port         TYPE srt_cfg_cli_asgn-port,
             url          TYPE srt_cfg_cli_asgn-url,
*             url          TYPE string,
           END OF ty_port.

    TYPES: BEGIN OF ty_dashboard_out,
             light        TYPE c LENGTH 1,
             service      TYPE srt_cfg_cli_asgn-proxy_class,
             logical_port TYPE srt_cfg_cli_asgn-lp_name,
             endpoint     TYPE string,
             status       TYPE ty_status_text,
             last_ok      TYPE string,
             trend        TYPE string,
             last_check   TYPE string,
           END OF ty_dashboard_out.

    DATA: mt_ports         TYPE TABLE OF ty_port,
          mt_dashboard_out TYPE TABLE OF ty_dashboard_out.

    METHODS:
      discover_ports,
      run_monitoring,
      view_dashboard,
      ping_endpoint
        IMPORTING iv_class  TYPE srt_cfg_cli_asgn-proxy_class
                  iv_lp     TYPE srt_cfg_cli_asgn-lp_name
        EXPORTING ev_status TYPE i
                  ev_error  TYPE string
                  ev_result TYPE ty_status_text,
      log_to_bal
        IMPORTING is_port   TYPE ty_port
                  iv_result TYPE ty_status_text
                  iv_status TYPE i
                  iv_error  TYPE string,
      read_previous_state
        IMPORTING iv_lp_name         TYPE srt_lp-lp_name
        RETURNING VALUE(rv_prev_sev) TYPE bal_s_msg-msgty,
      send_alert_mail
        IMPORTING is_port   TYPE ty_port
                  iv_result TYPE ty_status_text
                  iv_status TYPE i
                  iv_error  TYPE string,
      map_trend
        IMPORTING iv_latest       TYPE symsgty
                  iv_prev         TYPE symsgty
        RETURNING VALUE(rv_trend) TYPE string,
      display_alv.
ENDCLASS.

*----------------------------------------------------------------------*
* CLASS lcl_integration_health IMPLEMENTATION
*----------------------------------------------------------------------*
CLASS lcl_integration_health IMPLEMENTATION.
  METHOD run.
    discover_ports( ).
    IF rb_mon = abap_true.
      run_monitoring( ).
    ELSE.
      view_dashboard( ).
    ENDIF.
  ENDMETHOD.

  METHOD discover_ports.
    SELECT lp_name, proxy_class AS service_name, url, host , port
      FROM srt_cfg_cli_asgn
      WHERE lp_name      IN @s_lp
        AND proxy_class  IN @s_serv
      INTO CORRESPONDING FIELDS OF TABLE @mt_ports.
  ENDMETHOD.

  METHOD run_monitoring.
    DATA: lv_status TYPE i,
          lv_error  TYPE string,
          lv_result TYPE ty_status_text,
          lv_prev   TYPE bal_s_msg-msgty,
          lv_curr   TYPE bal_s_msg-msgty.

    LOOP AT mt_ports INTO DATA(ls_port).
      ping_endpoint(
        EXPORTING iv_lp    = ls_port-lp_name
                  iv_class = ls_port-service_name
        IMPORTING ev_status = lv_status
                  ev_error  = lv_error
                  ev_result = lv_result ).

      lv_prev = read_previous_state( ls_port-lp_name ).

      log_to_bal(
        is_port   = ls_port
        iv_result = lv_result
        iv_status = lv_status
        iv_error  = lv_error ).

      " Map result to severity for alert check
      CASE lv_result.
        WHEN 'OK'.              lv_curr = 'S'.
        WHEN 'CONFIG_ERROR'.    lv_curr = 'E'.
        WHEN 'ASSIGNMENT_ERROR'.lv_curr = 'E'.
        WHEN OTHERS.            lv_curr = 'A'.
      ENDCASE.

      " Alert if it was OK and now it's not
      IF ( lv_prev = 'S' OR lv_prev = ' ' ) AND ( lv_curr = 'E' OR lv_curr = 'A' ).
        send_alert_mail(
          is_port   = ls_port
          iv_result = lv_result
          iv_status = lv_status
          iv_error  = lv_error ).
      ENDIF.
    ENDLOOP.
    MESSAGE 'Monitoring completed.' TYPE 'S'.
  ENDMETHOD.

  METHOD ping_endpoint.
    DATA: lx_config  TYPE REF TO cx_srt_wsp_assign_config,
          lx_config2 TYPE REF TO cx_srt_wsp_config.

    TRY.
        cl_srt_wsp_ws_admin_manager=>ping(
          i_consumer_name = iv_class
          i_lp_name       = iv_lp ).
        ev_status = 200.
        ev_error  = 'Ping Successful'.
        ev_result = 'OK'.
      CATCH cx_srt_wsp_assign_config INTO lx_config.
        ev_error  = lx_config->get_text( ).
        ev_status = 500.
        ev_result = 'ASSIGNMENT_ERROR'.
      CATCH cx_srt_wsp_config INTO lx_config2.
        ev_error  = lx_config2->get_text( ).
        ev_status = 500.
        ev_result = 'CONFIG_ERROR'.
      CATCH cx_root INTO DATA(lx_root).
        ev_error  = lx_root->get_text( ).
        ev_status = 500.
        ev_result = 'CONFIG_ERROR'. " Map general errors to CONFIG_ERROR as per plan
    ENDTRY.
  ENDMETHOD.

  METHOD log_to_bal.
    DATA: ls_log     TYPE bal_s_log,
          lv_handle  TYPE balloghndl,
          ls_msg     TYPE bal_s_msg,
          lt_handles TYPE bal_t_logh.

    ls_log-object    = 'ZSOA_MON'.
    ls_log-subobject = 'SOAP_CONN'.
    ls_log-aluser    = sy-uname.
    ls_log-alprog    = sy-repid.

    CALL FUNCTION 'BAL_LOG_CREATE'
      EXPORTING
        i_s_log      = ls_log
      IMPORTING
        e_log_handle = lv_handle
      EXCEPTIONS
        OTHERS       = 1.

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    ls_msg-msgid = '00'.
    ls_msg-msgno = '001'.
    ls_msg-msgv1 = is_port-lp_name.
    ls_msg-msgv2 = iv_result.
    ls_msg-msgv3 = |Status: { iv_status }|.
    ls_msg-msgv4 = iv_error.

    CASE iv_result.
      WHEN 'OK'.              ls_msg-msgty = 'S'.
      WHEN 'CONFIG_ERROR'.    ls_msg-msgty = 'E'.
      WHEN 'ASSIGNMENT_ERROR'.ls_msg-msgty = 'E'.
      WHEN OTHERS.            ls_msg-msgty = 'A'.
    ENDCASE.

    CALL FUNCTION 'BAL_LOG_MSG_ADD'
      EXPORTING
        i_log_handle = lv_handle
        i_s_msg      = ls_msg
      EXCEPTIONS
        OTHERS       = 1.

    APPEND lv_handle TO lt_handles.
    CALL FUNCTION 'BAL_DB_SAVE'
      EXPORTING
        i_t_log_handle = lt_handles
      EXCEPTIONS
        OTHERS         = 1.

    COMMIT WORK.
  ENDMETHOD.

  METHOD read_previous_state.
    DATA: ls_filter     TYPE bal_s_lfil,
          ls_obj        TYPE bal_s_obj,
          ls_sub        TYPE bal_s_sub,
          lt_hdr        TYPE balhdr_t,
          ls_hdr        TYPE balhdr,
          lt_msg_handle TYPE bal_t_msgh,
          ls_msg_handle TYPE balmsghndl,
          ls_msg        TYPE bal_s_msg,
          lt_log_header TYPE balhdr_t.

    ls_obj-sign = 'I'. ls_obj-option = 'EQ'. ls_obj-low = 'ZSOA_MON'.
    APPEND ls_obj TO ls_filter-object.
    ls_sub-sign = 'I'. ls_sub-option = 'EQ'. ls_sub-low = 'SOAP_CONN'.
    APPEND ls_sub TO ls_filter-subobject.

    " Optimization: Search only logs from the last 30 days
    DATA(lv_date_limit) = sy-datum - 30.
    APPEND VALUE #( sign = 'I' option = 'GE' low = lv_date_limit ) TO ls_filter-aldate.

    CALL FUNCTION 'BAL_DB_SEARCH'
      EXPORTING
        i_s_log_filter = ls_filter
      IMPORTING
        e_t_log_header = lt_hdr
      EXCEPTIONS
        log_not_found  = 1
        OTHERS         = 2.

    IF sy-subrc <> 0 OR lt_hdr IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT lt_hdr INTO ls_hdr.
      REFRESH: lt_log_header.
      APPEND ls_hdr TO lt_log_header.

      CALL FUNCTION 'BAL_DB_LOAD'
        EXPORTING
          i_t_log_header = lt_log_header
        IMPORTING
          e_t_msg_handle = lt_msg_handle
        EXCEPTIONS
          OTHERS         = 1.

      IF sy-subrc = 0.
        LOOP AT lt_msg_handle INTO ls_msg_handle.
          "get the message by reading through the log
          CALL FUNCTION 'BAL_LOG_MSG_READ'
            EXPORTING
              i_s_msg_handle = ls_msg_handle
            IMPORTING
              e_s_msg        = ls_msg
            EXCEPTIONS
              log_not_found  = 1
              msg_not_found  = 2
              OTHERS         = 3.
          IF sy-subrc = 0.
            IF ls_msg-msgv1 = iv_lp_name.
              rv_prev_sev = ls_msg-msgty.
              RETURN.
            ENDIF.
          ENDIF.

        ENDLOOP.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD view_dashboard.
    DATA: ls_filter     TYPE bal_s_lfil,
          ls_obj        TYPE bal_s_obj,
          ls_sub        TYPE bal_s_sub,
          lt_hdr        TYPE balhdr_t,
          ls_hdr        TYPE balhdr,
          lt_msg_handle TYPE bal_t_msgh,
          ls_msg_handle TYPE balmsghndl,
          ls_msg        TYPE bal_s_msg,
          lt_msg        TYPE TABLE OF bal_s_msg,
          lt_log_header TYPE balhdr_t,
          inc_timestmp  TYPE string.

    APPEND VALUE #( sign = 'I' option = 'EQ' low = 'ZSOA_MON' ) TO ls_filter-object.
    APPEND VALUE #( sign = 'I' option = 'EQ' low = 'SOAP_CONN' ) TO ls_filter-subobject.
    APPEND VALUE #( sign = 'I' option = 'GE' low = sy-datum - 30 ) TO ls_filter-aldate.

    CALL FUNCTION 'BAL_DB_SEARCH'
      EXPORTING
        i_s_log_filter = ls_filter
      IMPORTING
        e_t_log_header = lt_hdr
      EXCEPTIONS
        OTHERS         = 1.

    IF sy-subrc = 0 AND lt_hdr IS NOT INITIAL.
      CALL FUNCTION 'BAL_DB_LOAD'
        EXPORTING
          i_t_log_header = lt_hdr
        IMPORTING
          e_t_msg_handle = lt_msg_handle
        EXCEPTIONS
          OTHERS         = 1.
    ENDIF.

    TYPES: BEGIN OF ty_msg_full,
             lp_name TYPE srt_lp-lp_name,
             msgty   TYPE symsgty,
             datum   TYPE aldate,
             uzeit   TYPE altime,
             result  TYPE ty_status_text,
           END OF ty_msg_full.
    DATA: lt_msg_full TYPE TABLE OF ty_msg_full.
    LOOP AT lt_msg_handle INTO ls_msg_handle.
      "get the message by reading through the log
      CALL FUNCTION 'BAL_LOG_MSG_READ'
        EXPORTING
          i_s_msg_handle = ls_msg_handle
        IMPORTING
          e_s_msg        = ls_msg
        EXCEPTIONS
          log_not_found  = 1
          msg_not_found  = 2
          OTHERS         = 3.
      IF sy-subrc = 0.
        APPEND ls_msg TO lt_msg.
      ENDIF.

    ENDLOOP.
    LOOP AT lt_msg INTO ls_msg.
      MOVE ls_msg-time_stmp TO inc_timestmp.
      APPEND VALUE #( lp_name = ls_msg-msgv1
                      msgty   = ls_msg-msgty
                      datum   = inc_timestmp(8)
                      uzeit   = inc_timestmp+8(6)
                      result  = ls_msg-msgv2 && ',' && ls_msg-msgv3 && ',' && ls_msg-msgv4 ) TO lt_msg_full.
    ENDLOOP.

    SORT lt_msg_full BY lp_name ASCENDING datum DESCENDING uzeit DESCENDING.

    DATA: lv_latest_sev TYPE symsgty,
          lv_prev_sev   TYPE symsgty,
          lv_found      TYPE abap_bool,
          lv_index      TYPE i.

    LOOP AT mt_ports INTO DATA(ls_port).
      DATA(ls_out) = VALUE ty_dashboard_out(
        service      = ls_port-service_name
        logical_port = ls_port-lp_name
        endpoint     = ls_port-url
        status       = 'UNKNOWN'
        light        = ' ' ).

      DATA: lv_latest_sev TYPE symsgty,
            lv_prev_sev   TYPE symsgty,
            lv_found      TYPE abap_bool.
      SORT lt_msg_full BY lp_name.
      LOOP AT lt_msg_full INTO DATA(ls_m) WHERE lp_name = ls_port-lp_name.
*        IF lv_found = abap_false.
        DATA(ls_m_tmp) = ls_m.
        lv_prev_sev = 'X'.
        AT NEW lp_name.
          ls_m = ls_m_tmp.
          lv_latest_sev = ls_m-msgty.
          ls_out-status = ls_m-result.
          ls_out-last_check = |{ ls_m-datum DATE = ENVIRONMENT } { ls_m-uzeit TIME = ENVIRONMENT }|.
*          lv_found = abap_true.,
          CASE ls_m-msgty.
            WHEN 'S'. ls_out-light = '3'. " Green
            WHEN OTHERS. ls_out-light = '1'. " Red
          ENDCASE.
          CLEAR lv_prev_sev.
        ENDAT.

        IF lv_prev_sev IS NOT INITIAL.
          lv_prev_sev = ls_m-msgty.
        ENDIF.
        IF ls_m-msgty = 'S' AND ls_out-last_ok IS INITIAL.
          ls_out-last_ok = |{ ls_m-datum DATE = ENVIRONMENT } { ls_m-uzeit TIME = ENVIRONMENT }|.
        ENDIF.

        " Once we have latest, previous (for trend) and last_ok, we can stop for this port
        IF lv_found = abap_true AND lv_prev_sev <> 'X' AND ls_out-last_ok IS NOT INITIAL.
          EXIT.
        ENDIF.
      ENDLOOP.

      ls_out-trend = map_trend( iv_latest = lv_latest_sev iv_prev = lv_prev_sev ).

      IF ls_out-status IN s_stat.
        APPEND ls_out TO mt_dashboard_out.
      ENDIF.
    ENDLOOP.

    display_alv( ).
  ENDMETHOD.

  METHOD map_trend.
    IF iv_latest IS INITIAL.
      rv_trend = '→'.
      RETURN.
    ENDIF.

    IF iv_prev IS INITIAL.
      rv_trend = '→'.
      RETURN.
    ENDIF.

    IF iv_latest = 'S'. " Current is OK
      IF iv_prev = 'S'.
        rv_trend = '→'. " Unchanged OK
      ELSE.
        rv_trend = '↑'. " Recovered
      ENDIF.
    ELSE. " Current is Error
      IF iv_prev = 'S'.
        rv_trend = '↓'. " Degraded
      ELSE.
        rv_trend = '↓'. " Repeatedly failing
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD display_alv.
    DATA: lo_alv     TYPE REF TO cl_salv_table,
          lo_columns TYPE REF TO cl_salv_columns_table,
          lo_column  TYPE REF TO cl_salv_column_table.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv
          CHANGING  t_table      = mt_dashboard_out ).

        lo_columns = lo_alv->get_columns( ).
        lo_columns->set_optimize( abap_true ).
        lo_columns->set_exception_column( 'LIGHT' ).

        lo_column ?= lo_columns->get_column( 'LOGICAL_PORT' ).
        lo_column->set_long_text( 'Logical Port' ).
        lo_column ?= lo_columns->get_column( 'SERVICE' ).
        lo_column->set_long_text( 'Service Name' ).
        lo_column ?= lo_columns->get_column( 'TREND' ).
        lo_column->set_short_text( 'Trend' ).
        lo_column->set_alignment( if_salv_c_alignment=>centered ).
        lo_column ?= lo_columns->get_column( 'STATUS' ).
        lo_column->set_short_text( 'Status' ).
        lo_column ?= lo_columns->get_column( 'LAST_CHECK' ).
        lo_column->set_long_text( 'Last Check' ).
        lo_column ?= lo_columns->get_column( 'LAST_OK' ).
        lo_column->set_long_text( 'Last OK' ).
        lo_column ?= lo_columns->get_column( 'ENDPOINT' ).
        lo_column->set_long_text( 'Target Endpoint' ).

        lo_alv->display( ).
      CATCH cx_salv_msg.
    ENDTRY.
  ENDMETHOD.

  METHOD send_alert_mail.
    DATA: lo_send_request TYPE REF TO cl_bcs,
          lo_document     TYPE REF TO cl_document_bcs,
          lo_recipient    TYPE REF TO if_recipient_bcs,
          lt_body         TYPE bcsy_text,
          lv_email        TYPE ad_smtpadr.

    SELECT SINGLE low FROM tvarvc INTO @lv_email
      WHERE name = 'Z_CPI_ALERT_MAIL' AND type = 'P'.

    IF lv_email IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        lo_send_request = cl_bcs=>create_persistent( ).
        APPEND |CPI Connectivity Alert: { is_port-lp_name }| TO lt_body.
        APPEND |Result: { iv_result }| TO lt_body.
        APPEND |Error: { iv_error }| TO lt_body.
        APPEND |Endpoint: { is_port-url }| TO lt_body.

        lo_document = cl_document_bcs=>create_document(
                        i_type    = 'RAW'
                        i_text    = lt_body
                        i_subject = |CPI Alert: { is_port-lp_name }| ).
        lo_send_request->set_document( lo_document ).
        lo_recipient = cl_cam_address_bcs=>create_internet_address( lv_email ).
        lo_send_request->add_recipient( lo_recipient ).
        lo_send_request->send( ).
        COMMIT WORK.
      CATCH cx_bcs.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  NEW lcl_integration_health( )->run( ).
