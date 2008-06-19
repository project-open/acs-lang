ad_page_contract {

    Displays the localized message from the database for translation (displays
    an individual message)

    @author Bruno Mattarollo <bruno.mattarollo@ams.greenpeace.org>
    @author Christian Hvid
    @creation-date 30 October 2001
    @cvs-id $Id$

} {
    locale
    package_key
    message_key
    show:optional
    {usage_p "f"}
    {return_url {}}
}

# We rename to avoid conflict in queries
set current_locale $locale
set default_locale en_US

set locale_label [ad_locale_get_label $current_locale]
set default_locale_label [ad_locale_get_label $default_locale]

set page_title "Edit $package_key.$message_key"
set context [list [list [export_vars -base package-list { locale }] $locale_label] \
                 [list [export_vars -base message-list { locale package_key show }] $package_key] \
                 "$package_key.$message_key"]


# We let you create/delete messages keys if you're in the default locale
set create_p [string equal $current_locale $default_locale]

set description_edit_url [export_vars -base edit-description { locale package_key message_key show }]

set usage_hide_url [export_vars -base [ad_conn url] { locale package_key message_key show return_url }]
set usage_show_url [export_vars -base [ad_conn url] { locale package_key message_key show {usage_p 1} return_url }]

set delete_url [export_vars -base message-delete { locale package_key message_key show {return_url {[ad_return_url]}} }]


ad_form -name message -form {
    {locale:text(hidden),optional {value $current_locale}}
    {package_key:text(hidden),optional {value $package_key}}
    {message_key:text(hidden),optional {value $message_key}}
    {show:text(hidden),optional}
    {return_url:text(hidden),optional {value $return_url}}

    {message_key_pretty:text(inform)
        {label "Message Key"}
        {value "$package_key.$message_key"}
    }
    {description:text(inform)
        {label "Description"}
        {after_html {}}
    }
} 

if { ![string equal $default_locale $current_locale] } {
    ad_form -extend -name message -form {
        {original_message:text(inform)
            {label "$default_locale_label Message"}
        }
    }
}
    
ad_form -extend -name message -form {
    {message:text(textarea)
        {label "$locale_label Message"} 
        {html { rows 6 cols 40 }}
    }
    {comment:text(textarea),optional
        {label "Comment"}
        {html { rows 6 cols 40 }}
    }
    {submit:text(submit)
        {label "     Update     "}
    }
} -on_request {
    set original_message {}
    set description {}

    db_0or1row select_original_message {
        select lm.message as original_message,
               lmk.description
        from   lang_messages lm,
               lang_message_keys lmk
        where  lm.message_key = lmk.message_key
        and    lm.package_key = lmk.package_key
        and    lm.package_key = :package_key
        and    lm.message_key = :message_key
        and    lm.locale = :default_locale
    }

    set translated_p [db_0or1row select_translated_message {
        select lm.message as message,
               cu.first_names || ' ' || cu.last_name as creation_user_name,
               cu.user_id as creation_user_id,
               to_char(lm.creation_date, 'YYYY-MM-DD') as creation_date
        from   lang_messages lm,
               cc_users cu
        where  lm.package_key = :package_key
        and    lm.message_key = :message_key
        and    lm.locale = :current_locale
        and    cu.user_id = lm.creation_user
    }]

    set original_message [ad_quotehtml $original_message]
    if { [exists_and_not_null message] } {
        set message $message
    } else {
	set message $original_message
    }

    if { [empty_string_p $description] } {
        set description [subst {(<a href="$description_edit_url">add description</a>)}]
    } else {
        set description "[ad_text_to_html -- $description] [subst { (<a href="$description_edit_url">edit</a>)}]"
    }

    # Augment the audit trail with info on who created the first message
    if { ![string equal $current_locale $default_locale] && $translated_p } {
        set edited_p [db_string edit_count {
            select count(*)
            from lang_messages_audit
            where package_key = :package_key
              and message_key = :message_key
              and locale = :current_locale
        }]

        if { $edited_p } {
            # The translation has been edited
            # Get the creation user of the first revision
            db_1row select_first_revision {
               select cu.first_names || ' ' || cu.last_name as creation_user_name,
                      cu.user_id as creation_user_id,
                      to_char(lma.overwrite_date, 'YYYY-MM-DD') as creation_date
               from lang_messages_audit lma,
                    cc_users cu
               where  lma.package_key = :package_key
               and    lma.message_key = :message_key
               and    lma.locale = :current_locale
               and    cu.user_id = lma.overwrite_user
               and    lma.audit_id = (select min(lm2.audit_id)
                                     from lang_messages_audit lm2
                                     where  lm2.package_key = :package_key
                                     and    lm2.message_key = :message_key
                                     and    lm2.locale = :current_locale
                                     )                                     
            }
        } 

        set first_translated_message "<ul> <li>First translated by [acs_community_member_link -user_id $creation_user_id -label $creation_user_name] on $creation_date</li></ul>"
    } else {
        set first_translated_message ""
    }
} -on_submit {

    # Register message via acs-lang
    lang::message::register -comment $comment $locale $package_key $message_key $message


    # Send a message to the language server
    catch {
	set package_version [db_string package_version "select max(version_name) from apm_package_versions where package_key = :package_key" -default ""]
	set system_owner_email [ad_parameter -package_id [ad_acs_kernel_id] SystemOwner "" [ad_system_owner]]
	set sender_email [db_string sender_email "select email as sender_email from parties where party_id = [ad_get_user_id]" -default $system_owner_email]
	set sender_first_names [db_string sender_email "select first_names from persons where person_id = [ad_get_user_id]" -default "System"]
	set sender_last_name [db_string sender_email "select last_name from persons where person_id = [ad_get_user_id]" -default "Administrator"]
	set lang_server_base_url "http://berlin.dnsalias.com/acs-lang/lang-message-register"
	set lang_server_base_url [parameter::get_from_package_key -package_key "acs-lang" -parameter "LangServerURL" -default $lang_server_base_url]
	set lang_server_timeout [parameter::get_from_package_key -package_key "acs-lang" -parameter "LangServerTimeout" -default 5]
	set lang_server_url [export_vars -base $lang_server_base_url {locale package_key message_key message comment package_version sender_email sender_first_names sender_last_name}]
	
	ns_httpget $lang_server_url $lang_server_timeout
    } err_msg
    

    if { [empty_string_p $return_url] } {
        set return_url "[ad_conn url]?[export_vars { locale package_key message_key show }]"
    }
    ad_returnredirect $return_url
    ad_script_abort
}
