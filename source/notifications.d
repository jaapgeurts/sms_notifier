module notifications;

import std.functional : toDelegate;
import std.conv : to;

import xclipboard;
import wlclipboard;

import ddbus;
import ddbus.c_lib;

import logging;
import modem;

private enum NotificationClosedReason {
    Expired = 1,
    DismissedByUser = 2,
    ClosedByCode = 3,
    UndefinedReserved = 4
}

private struct Notification {
    uint id;
    string sms_path;
    string number;
}

private Notification[uint] notifications;

void DBusClientNotificationsProc(Connection sessbus, LogLevel ll) {

    setDefaultLoggingLevel(ll);
    logdebug("Starting dbus notification thread");

    // setup router for receiving message from notifications
    // receive message
    DBusError err;
    dbus_bus_add_match(sessbus.conn,
        "type='signal',interface='org.freedesktop.Notifications'",
        &err); // allow to receive signals from the given interface
    dbus_connection_flush(sessbus.conn);

    auto router = new MessageRouter();
    MessagePattern patt = MessagePattern(ObjectPath("/org/freedesktop/Notifications"),
        interfaceName("org.freedesktop.Notifications"),
        "ActionInvoked", true);
    router.setHandler!(void, uint, string)(patt, toDelegate(&onNotificationActionInvoked));

    MessagePattern patt3 = MessagePattern(ObjectPath("/org/freedesktop/Notifications"),
        interfaceName("org.freedesktop.Notifications"),
        "NotificationClosed", true);
    router.setHandler!(void, uint, uint)(patt3, toDelegate(&onNotificationClosed));

    // install router
    logdebug("DBUS: Waiting for notification messages");
    registerRouter(sessbus, router);
}

void sendNotification(string text, string sms_dbus_path, string totp_number) {

    Connection conn = connectToBus();
    // Send message
    DBusError error;
    PathIface dbus_notify = new PathIface(conn,
        busName("org.freedesktop.Notifications"),
        ObjectPath("/org/freedesktop/Notifications"),
        interfaceName("org.freedesktop.Notifications"));
    string[] list; // must have even num elements. even elem = action, odd elem = message to user
    list ~= "copy"; //action key for use with notification handler
    list ~= "Copy " ~ totp_number; // user message
    list ~= "copydelete";
    list ~= "Copy " ~ totp_number ~ " and delete";

    ddbus.Variant!DBusAny[string] hints;

    hints["image-path"] = variant(DBusAny("message-new"));
    hints["desktop-entry"] = variant(DBusAny("smsnotifier"));

    // TODO: allow configuratin of timeout. currently is is 10.000 ms
    Message msg = dbus_notify.Notify("SMS Received", cast(uint) 0,
        "mail-message-new-list",
        "A SMS message was received",
        text, list, hints, -1);

    uint id = msg.to!uint();
    Notification notification = Notification(id, sms_dbus_path, totp_number);
    notifications[id] = notification;
    loginfo("Created notification with id: ", id);
}


private void onNotificationActionInvoked(uint id, string action_key) {
    logdebug("notificationActionInvoked(): " ~ to!string(id) ~ ", action: " ~ action_key);
    // TODO: check if id is a notification that I sent
    Notification* notification = id in notifications;
    if (notification == null) {
        logdebug("Ignoring action '" ~ action_key ~ "' for non-owned notification.");
        return;
    }

    if (action_key == "copy" || action_key == "copydelete") {
        loginfo("copy to clip: Id: ", id, " value: " ~ notification.number);

        claimClipboardSelection(notification.number, loggingLevel); // returns immediately
    // TODO: wait if succesful and only then delete the SMS
    }

    if (action_key == "copydelete") {
        deleteSmsMessage(notification.sms_path);
    }
}

private void onNotificationClosed(uint id, uint reason) {
    if (id !in notifications) {
        logdebug("Notification closed but not mine. Not taking action.");
        return;
    }
    loginfo("Closed notification: ", id, " reasoncode: ", reason.to!NotificationClosedReason);
    notifications.remove(id);
    loginfo("Messages in list: ", notifications.keys);
}
