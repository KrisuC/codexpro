"""Window-scoped Snapshot compatibility overlay for Windows-MCP 0.8.7.

The upstream region filter includes overlapping background windows. Restrict
UIA traversal before collection to the topmost native window under the ROI.
This is a privacy default, not an OS sandbox or an authorization mechanism.
"""
import threading
from importlib.metadata import version
import win32gui
from windows_mcp.desktop.service import Desktop

if version("windows-mcp") != "0.8.7":
    raise RuntimeError("Revalidate the window-scoping overlay before upgrading Windows-MCP")
_local = threading.local()
_lock = threading.RLock()
_get_state = Desktop.get_state
_get_controls = Desktop.get_controls_handles
_get_windows = Desktop.get_windows
_get_active = Desktop.get_active_window


def _controls(self, optimized=False):
    handle = getattr(_local, "handle", None)
    return {handle} if handle else _get_controls(self, optimized=optimized)


def _windows(self, controls_handles=None):
    windows, handles = _get_windows(self, controls_handles)
    target = getattr(_local, "handle", None)
    if target:
        windows = [window for window in windows if window.handle == target]
        handles = {target} if windows else set()
    return windows, handles


def _active(self, windows=None):
    target = getattr(_local, "handle", None)
    if target and win32gui.GetForegroundWindow() != target:
        return None
    result = _get_active(self, windows)
    return result if not target or result is None or result.handle == target else None


def _scoped_state(self, *args, **kwargs):
    region = kwargs.get("region")
    ui = kwargs.get("use_ui_tree", True)
    ui = ui is True or isinstance(ui, str) and ui.lower() == "true"
    vision = kwargs.get("use_vision", False)
    vision = vision is True or isinstance(vision, str) and vision.lower() == "true"
    if not region:
        state = _get_state(self, *args, **kwargs)
        if not ui and not vision:
            # Metadata-only discovery needs window names/handles, not UI text.
            windows, _ = _get_windows(self, _get_controls(self))
            active = _get_active(self, windows)
            state.active_window = active
            state.windows = [window for window in windows if active is None or window.handle != active.handle]
        return state
    if not ui:
        state = _get_state(self, *args, **kwargs)
        state.active_desktop = {"name": "Not included in window-scoped capture"}
        state.all_desktops = []
        return state
    self.parse_region_selection(region)  # Reject invalid/out-of-bounds coordinates.
    left, top, right, bottom = tuple(region)
    handle = win32gui.WindowFromPoint(((left + right) // 2, (top + bottom) // 2))
    handle = win32gui.GetAncestor(handle, 2) if handle else None  # GA_ROOT
    if not handle or not win32gui.IsWindowVisible(handle) or win32gui.IsIconic(handle):
        raise ValueError("No visible target window under the supplied region")
    x1, y1, x2, y2 = win32gui.GetWindowRect(handle)
    if left < x1 or top < y1 or right > x2 or bottom > y2:
        raise ValueError("UI inspection region spans multiple windows; inspect each window separately")
    with _lock:
        _local.handle = handle
        try:
            state = _get_state(self, *args, **kwargs)
            if any(window.handle != handle for window in state.windows):
                raise ValueError("Window-scoped snapshot contained unexpected window metadata")
            state.active_desktop = {"name": "Not included in window-scoped capture"}
            state.all_desktops = []
            return state
        finally:
            _local.handle = None


Desktop.get_controls_handles = _controls
Desktop.get_windows = _windows
Desktop.get_active_window = _active
Desktop.get_state = _scoped_state

from windows_mcp.__main__ import main
main()
