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
