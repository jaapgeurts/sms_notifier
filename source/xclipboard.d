module xclipboard;

import std.concurrency;
import std.string : toStringz;

import x11.Xlib;
import x11.Xatom;
import x11.X;

import logging;

void claimClipboardSelection(string text, LogLevel ll) {

    // This makes me the owner of the selection
    // Which means keep checking XEvents to send the data upon request.
    // Until I lose the selection in the clear statement.

    Tid threadId = spawn(&selectionProc, text, ll);

}

private void selectionProc(string text, LogLevel ll) {

    setDefaultLoggingLevel(ll);
    loginfo("Starting x selection thread");

    Display* display;
    Window window;
    Atom targets_atom, text_atom, UTF8, XA_ATOM = 4, XA_STRING = 31;
    Atom selection;

    display = XOpenDisplay(null);
    if (display == null)
        throw new Exception("Can't open display");
    int N = DefaultScreen(display);
    window = XCreateSimpleWindow(display, RootWindow(display, N), 0, 0, 1, 1, 0,
        BlackPixel(display, N), WhitePixel(display, N));
    if (window ==  None ) {
        logerror("Can't create window");
        return;
    }
    targets_atom = XInternAtom(display, "TARGETS", 0);
    if (targets_atom ==  None) {
        logerror("Can't get atom TARGETS");
        return;
    }
    text_atom = XInternAtom(display, "TEXT", 0);
    if (text_atom ==  None) {
        logerror ("Can't get atom TEXT");
        return;
    }
    UTF8 = XInternAtom(display, "UTF8_STRING", 1);
    if (UTF8 == None)
        UTF8 = XA_STRING;
    selection = XInternAtom(display, "CLIPBOARD", 0);
    if (selection == None) {
        logerror("Can't get atom CLIPBOARD");
    }
    logdebug("Clipboard open");

    XSetSelectionOwner(display, selection, window, 0);
    if (XGetSelectionOwner(display, selection) != window) {
        logerror("Failed to get selection ownership");
        return;
    }

    bool ownSelection = true;

    XEvent event;
    const char* textarray = text.toStringz;

    while (ownSelection) {
        XNextEvent(display, &event);
        final switch (event.type) {
        case SelectionRequest:
            if (event.xselectionrequest.selection != selection)
                break;
            XSelectionRequestEvent* xsr = &event.xselectionrequest;
            XSelectionEvent ev = {0};
            int R = 0;
            ev.type = SelectionNotify;
            ev.display = xsr.display;
            ev.requestor = xsr.requestor,
            ev.selection = xsr.selection;
            ev.time = xsr.time;
            ev.target = xsr.target;
            ev.property = xsr.property;
            if (ev.target == targets_atom)
                R = XChangeProperty(ev.display, ev.requestor, ev.property, XA_ATOM, 32,
                    PropModeReplace, cast(ubyte*)&UTF8, 1);
            else if (ev.target == XA_STRING || ev.target == text_atom)
                R = XChangeProperty(ev.display, ev.requestor, ev.property, XA_STRING, 8, PropModeReplace, cast(
                        ubyte*) textarray, cast(int) text
                        .length);
            else if (ev.target == UTF8)
                R = XChangeProperty(ev.display, ev.requestor, ev.property, UTF8, 8, PropModeReplace, cast(
                        ubyte*) textarray, cast(int) text
                        .length);
            else
                ev.property = None;
            if ((R & 2) == 0) {
                loginfo("XClipboard::SelectionRequest. Storing data in atom");
                XSendEvent(display, ev.requestor, 0, 0, cast(XEvent*)&ev);
            }
            break;
        case SelectionClear:
            ownSelection = false;
            loginfo("XClipboard::SelectionClear.");
        }
    }

    logdebug("Clipboard closed");
    if (window)
        XDestroyWindow(display, window);
    if (display != null)
        XCloseDisplay(display);

}
