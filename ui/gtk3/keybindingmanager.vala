/* vim:set et sts=4 sw=4:
valac --pkg gtk+-2.0 --pkg x11 --pkg gdk-x11-2.0 --pkg gee-1.0 keybinding-manager.vala
*/

/**
 * This class is in charge to grab keybindings on the X11 display
 * and filter X11-events and passing on such events to the registed
 * handler methods.
 *
 * @author Oliver Sauder <os@esite.ch>
 */

using Gdk;
using GLib;
using Gtk;
using X;

extern bool grab_keycode (Gdk.Display display,
                          uint keyval,
                          uint modifiers);

extern bool ungrab_keycode (Gdk.Display display,
                            uint keyval,
                            uint modifiers);

public class KeybindingManager : GLib.Object {
    /**
     * list of binded keybindings
     */
    private GLib.List<Keybinding> m_bindings = new GLib.List<Keybinding>();

    private static KeybindingManager m_instance = null;

    public static const uint MODIFIER_FILTER =
        Gdk.ModifierType.MODIFIER_MASK & ~(
        Gdk.ModifierType.MOD2_MASK |
        Gdk.ModifierType.LOCK_MASK |
        Gdk.ModifierType.MOD4_MASK |
        Gdk.ModifierType.MOD5_MASK);

    /**
     * Helper class to store keybinding
     */
    private class Keybinding {
        public Keybinding(string accelerator,
                          uint keysym,
                          Gdk.ModifierType modifiers,
                          KeybindingHandlerFunc handler) {
            this.accelerator = accelerator;
            this.keysym = keysym;
            this.modifiers = modifiers;
            this.handler = handler;
        }

        public string accelerator { get; set; }
        public uint keysym { get; set; }
        public Gdk.ModifierType modifiers { get; set; }
        public unowned KeybindingHandlerFunc handler { get; set; }
    }

    /**
     * Keybinding func needed to bind key to handler
     *
     * @param event passing on gdk event
     */
    public delegate void KeybindingHandlerFunc(Gdk.Event event);


    private  KeybindingManager() {
        Gdk.Event.handler_set(event_handler);
    }

    /**
     * Bind accelerator to given handler
     *
     * @param accelerator accelerator parsable by Gtk.accelerator_parse
     * @param handler handler called when given accelerator is pressed
     */
    public bool bind(string accelerator,
                     KeybindingHandlerFunc handler) {
        debug("Binding key " + accelerator);

        // convert accelerator
        uint keysym;
        Gdk.ModifierType modifiers;
        Gtk.accelerator_parse(accelerator, out keysym, out modifiers);

        get_primary_modifier(modifiers);

        unowned X.Display display = Gdk.x11_get_default_xdisplay();

        int keycode = display.keysym_to_keycode(keysym);

        if (keycode == 0)
            return false;

        grab_keycode (Gdk.Display.get_default(), keysym, modifiers);

        // store binding
        Keybinding binding = new Keybinding(accelerator,
                                            keysym, modifiers,
                                            handler);
        m_bindings.append(binding);

        debug("Successfully binded key " + accelerator);
        return true;
    }

    /**
     * Unbind given accelerator.
     *
     * @param accelerator accelerator parsable by Gtk.accelerator_parse
     */
    public void unbind (string accelerator) {
        debug("Unbinding key " + accelerator);

        // unbind all keys with given accelerator
        GLib.List<Keybinding> remove_bindings = new GLib.List<Keybinding>();
        foreach(Keybinding binding in m_bindings) {
            if(str_equal(accelerator, binding.accelerator)) {
                ungrab_keycode (Gdk.Display.get_default(),
                                binding.keysym,
                                binding.modifiers);
                remove_bindings.append(binding);
            }
        }

        // remove unbinded keys
        foreach (Keybinding binding in remove_bindings)
            m_bindings.remove (binding);
    }

    public static KeybindingManager get_instance () {
        if (m_instance == null)
            m_instance = new KeybindingManager ();
        return m_instance;
    }

    public static uint get_primary_modifier (uint binding_mask) {
        const uint[] masks = {
            Gdk.ModifierType.MOD5_MASK,
            Gdk.ModifierType.MOD4_MASK,
            Gdk.ModifierType.MOD3_MASK,
            Gdk.ModifierType.MOD2_MASK,
            Gdk.ModifierType.MOD1_MASK,
            Gdk.ModifierType.CONTROL_MASK,
            Gdk.ModifierType.SHIFT_MASK,
            Gdk.ModifierType.LOCK_MASK
        };
        foreach (var mask in masks) {
            if ((binding_mask & mask) == mask)
                return mask;
        }
        return 0;
    }

    public static bool primary_modifier_still_pressed(Gdk.Event event,
                                                      uint primary_modifier) {
        Gdk.EventKey keyevent = event.key;
        if (primary_modifier == 0)
            return false;

        Gdk.Device device = event.get_device();
        Gdk.Device pointer;
        if (device.get_source() == Gdk.InputSource.KEYBOARD)
            pointer = device.get_associated_device();
        else
            pointer = device;

        uint modifier = 0;
        pointer.get_state(keyevent.window, null, out modifier);
        if ((primary_modifier & modifier) == primary_modifier)
            return true;

        return false;
    }

    public static uint keyval_to_modifier (uint keyval) {
        switch(keyval) {
            case 0xffe3: /* Control_L */
            case 0xffe4: /* Control_R */
                return Gdk.ModifierType.CONTROL_MASK;
            case 0xffe1: /* Shift_L */
            case 0xffe2: /* Shift_R */
                return Gdk.ModifierType.SHIFT_MASK;
            case 0xffe5: /* Caps_Lock */
                return Gdk.ModifierType.LOCK_MASK;
            case 0xffe9: /* Alt_L */
            case 0xffea: /* Alt_R */
                return Gdk.ModifierType.MOD1_MASK;
            case 0xffe7: /* Meta_L */
            case 0xffe8: /* Meta_R */
                return Gdk.ModifierType.META_MASK;
            case 0xffeb: /* Super_L */
            case 0xffec: /* Super_R */
                return Gdk.ModifierType.SUPER_MASK;
            case 0xffed: /* Hyper_L */
            case 0xffee: /* Hyper_R */
                return Gdk.ModifierType.HYPER_MASK;
            default:
                return 0;
        }
    }

    private void event_handler(Gdk.Event event) {
        do {
            if (event.any.window != Gdk.get_default_root_window())
                break;

            if (event.type == Gdk.EventType.KEY_PRESS) {
                uint modifiers = event.key.state & MODIFIER_FILTER;
                foreach (var binding in m_bindings) {
                    if (event.key.keyval != binding.keysym ||
                        modifiers != binding.modifiers)
                        continue;
                    binding.handler(event);
                    return;
                }
            }
        } while (false);
        Gtk.main_do_event(event);
    }
}

/*
public static int main (string[] args)
{
    Gtk.init (ref args);

    KeybindingManager manager = new KeybindingManager();
    manager.bind("<Ctrl><Alt>V", test);

    Gtk.main ();
    return 0;
}

private static void test()
{
    debug("hotkey pressed");
}
*/
