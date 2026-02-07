*&---------------------------------------------------------------------*
*& Report Z_CPI_SOAP_MONITOR
*&---------------------------------------------------------------------*
REPORT z_cpi_soap_monitor.

CLASS lcl_monitor DEFINITION.

  PUBLIC SECTION.
    METHODS run.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_logical_port,
             logical_port TYPE srt_lp-lp_name,
             service_name TYPE srt_lp-service_name,
             endpoint_url TYPE string,
           END OF ty_logical_port.

    DATA: mt_ports TYPE TABLE OF ty_logical_port.

    METHODS get_cpi_logical_ports.
    METHODS ping_endpoint
      IMPORTING iv_url    TYPE string
      EXPORTING ev_status TYPE i
                ev_error  TYPE string.
    METHODS classify_result
      IMPORTING iv_status        TYPE i
                iv_error         TYPE string
      RETURNING VALUE(rv_result) TYPE string.
    METHODS log_to_bal
      IMPORTING is_port   TYPE ty_logical_port
                iv_result TYPE string
                iv_status TYPE i
                iv_error  TYPE string.
    METHODS read_previous_state
      IMPORTING iv_lp_name         TYPE srt_lp-lp_name
      RETURNING VALUE(rv_prev_sev) TYPE bal_s_msg-msgty.
    METHODS send_alert_mail
      IMPORTING is_port   TYPE ty_logical_port
                iv_result TYPE string
                iv_status TYPE i
                iv_error  TYPE string.

ENDCLASS.

CLASS lcl_monitor IMPLEMENTATION.

  METHOD run.
    get_cpi_logical_ports( ).

    LOOP AT mt_ports INTO DATA(ls_port).
      DATA: lv_status TYPE i,
            lv_error  TYPE string,
            lv_result TYPE string,
            lv_prev   TYPE bal_s_msg-msgty,
            lv_curr   TYPE bal_s_msg-msgty.

      ping_endpoint(
        EXPORTING iv_url    = ls_port-endpoint_url
        IMPORTING ev_status = lv_status
                  ev_error  = lv_error ).

      lv_result = classify_result( iv_status = lv_status iv_error = lv_error ).

      lv_prev = read_previous_state( ls_port-logical_port ).

      log_to_bal(
        is_port   = ls_port
        iv_result = lv_result
        iv_status = lv_status
        iv_error  = lv_error ).

      CASE lv_result.
        WHEN 'OK'.        lv_curr = 'S'.
        WHEN 'AUTH'.      lv_curr = 'W'.
        WHEN 'CPI_ERROR'. lv_curr = 'E'.
        WHEN 'DOWN'.      lv_curr = 'A'.
      ENDCASE.

      IF lv_prev = 'S' AND ( lv_curr = 'E' OR lv_curr = 'A' ).
        send_alert_mail(
          is_port   = ls_port
          iv_result = lv_result
          iv_status = lv_status
          iv_error  = lv_error ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_cpi_logical_ports.
    SELECT lp~lp_name AS logical_port,
           lp~service_name,
           url~url AS endpoint_url
      FROM srt_lp AS lp
      INNER JOIN srt_lp_url AS url ON lp~lp_name = url~lp_name
      WHERE url~url LIKE '%hana.ondemand.com%'
      INTO CORRESPONDING FIELDS OF TABLE @mt_ports.
  ENDMETHOD.

  METHOD ping_endpoint.
    DATA: lo_client TYPE REF TO if_http_client.

    cl_http_client=>create_by_url(
      EXPORTING
        url    = iv_url
      IMPORTING
        client = lo_client
      EXCEPTIONS
        argument_not_found = 1
        plugin_not_active  = 2
        internal_error     = 3
        OTHERS             = 4 ).

    IF sy-subrc <> 0.
      ev_status = 0.
      ev_error  = 'Error creating HTTP client'.
      RETURN.
    ENDIF.

    lo_client->send(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        http_invalid_timeout       = 4
        OTHERS                     = 5 ).

    IF sy-subrc <> 0.
      lo_client->get_last_error( IMPORTING message = ev_error ).
      ev_status = 0.
      lo_client->close( ).
      RETURN.
    ENDIF.

    lo_client->receive(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        OTHERS                     = 4 ).

    IF sy-subrc <> 0.
      lo_client->get_last_error( IMPORTING message = ev_error ).
      ev_status = 0.
      lo_client->close( ).
      RETURN.
    ENDIF.

    lo_client->response->get_status( IMPORTING code = ev_status ).
    lo_client->close( ).
  ENDMETHOD.

  METHOD classify_result.
    IF iv_status = 200.
      rv_result = 'OK'.
    ELSEIF iv_status = 401 OR iv_status = 403.
      rv_result = 'AUTH'.
    ELSEIF iv_status >= 500.
      rv_result = 'CPI_ERROR'.
    ELSE.
      rv_result = 'DOWN'.
    ENDIF.
  ENDMETHOD.

  METHOD log_to_bal.
    DATA: ls_log      TYPE bal_s_log,
          lv_handle   TYPE balloghndl,
          ls_msg      TYPE bal_s_msg,
          lt_handles  TYPE bal_t_logh.

    ls_log-object    = 'ZCPI_MON'.
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
    ls_msg-msgv1 = is_port-logical_port.
    ls_msg-msgv2 = iv_result.
    ls_msg-msgv3 = |Status: { iv_status }|.
    ls_msg-msgv4 = iv_error.

    CASE iv_result.
      WHEN 'OK'.        ls_msg-msgty = 'S'.
      WHEN 'AUTH'.      ls_msg-msgty = 'W'.
      WHEN 'CPI_ERROR'. ls_msg-msgty = 'E'.
      WHEN 'DOWN'.      ls_msg-msgty = 'A'.
      WHEN OTHERS.      ls_msg-msgty = 'I'.
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
  ENDMETHOD.

  METHOD read_previous_state.
    DATA: ls_filter     TYPE bal_s_lfil,
          ls_obj        TYPE bal_s_obj,
          ls_sub        TYPE bal_s_sub,
          lt_hdr        TYPE balhdr_t,
          ls_hdr        TYPE balhdr,
          lt_msgs       TYPE bal_t_mscl,
          ls_msg        TYPE bal_mscl,
          lt_log_header TYPE balhdr_t.

    ls_obj-sign = 'I'. ls_obj-option = 'EQ'. ls_obj-low = 'ZCPI_MON'.
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

    SORT lt_hdr BY aldate DESC altime DESC.

    LOOP AT lt_hdr INTO ls_hdr.
      REFRESH: lt_log_header, lt_msgs.
      APPEND ls_hdr TO lt_log_header.

      CALL FUNCTION 'BAL_DB_LOAD'
        EXPORTING
          i_t_log_header = lt_log_header
        IMPORTING
          e_t_msg        = lt_msgs
        EXCEPTIONS
          OTHERS         = 1.

      IF sy-subrc = 0.
        LOOP AT lt_msgs INTO ls_msg WHERE msgv1 = iv_lp_name.
          rv_prev_sev = ls_msg-msgty.
          RETURN.
        ENDLOOP.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD send_alert_mail.
    DATA: lo_send_request TYPE REF TO cl_bcs,
          lo_document     TYPE REF TO cl_document_bcs,
          lo_recipient    TYPE REF TO if_recipient_bcs,
          lt_body         TYPE bcsy_text,
          lv_email        TYPE ad_smtpadr,
          lv_subject      TYPE so_obj_des.

    SELECT SINGLE value FROM tvarvc INTO @lv_email
      WHERE name = 'Z_CPI_ALERT_MAIL' AND type = 'P'.

    IF lv_email IS INITIAL.
      lv_email = 'cpi-integration-alerts@company.com'.
    ENDIF.

    TRY.
        lo_send_request = cl_bcs=>create_persistence( ).
        lv_subject = |CPI Alert: { is_port-logical_port } - { iv_result }|.

        APPEND |CPI Connectivity Alert| TO lt_body.
        APPEND |----------------------| TO lt_body.
        APPEND |Logical Port: { is_port-logical_port }| TO lt_body.
        APPEND |Service Name: { is_port-service_name }| TO lt_body.
        APPEND |Endpoint:     { is_port-endpoint_url }| TO lt_body.
        APPEND |Result:       { iv_result }| TO lt_body.
        APPEND |HTTP Status:  { iv_status }| TO lt_body.
        APPEND |Error:        { iv_error }| TO lt_body.
        APPEND |System ID:    { sy-sysid }| TO lt_body.
        APPEND |Timestamp:    { sy-datum DATE = ENVIRONMENT } { sy-uzeit TIME = ENVIRONMENT }| TO lt_body.

        lo_document = cl_document_bcs=>create_document(
                        i_type    = 'RAW'
                        i_text    = lt_body
                        i_subject = lv_subject ).

        lo_send_request->set_document( lo_document ).
        lo_recipient = cl_cam_address_bcs=>create_internet_address( lv_email ).
        lo_send_request->add_recipient( lo_recipient ).
        lo_send_request->set_send_immediately( abap_true ).
        lo_send_request->send( ).
        COMMIT WORK.
      CATCH cx_bcs.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  NEW lcl_monitor( )->run( ).
