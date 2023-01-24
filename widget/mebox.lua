local capi = {
    awesome = awesome,
    mousegrabber = mousegrabber,
    screen = screen,
    mouse = mouse,
}
local setmetatable = setmetatable
local ipairs = ipairs
local math = math
local awful = require("awful")
local beautiful = require("beautiful")
local gtable = require("gears.table")
local wibox = require("wibox")
local base = require("wibox.widget.base")
local binding = require("io.binding")
local mod = binding.modifier
local btn = binding.button
local widget_helper = require("helpers.widget")
local noice = require("widget.noice")


local function get_screen(screen)
    return screen and capi.screen[screen]
end

local mebox = { mt = {} }

function mebox.separator(menu)
    return {
        enabled = false,
        template = menu.separator_template,
    }
end

function mebox.header(text)
    return function(menu)
        return {
            enabled = false,
            text = text,
            template = menu.header_template,
        }
    end
end

local function default_placement(menu, args)
    local border_width = menu.border_width
    local width = menu.width + 2 * border_width
    local height = menu.height + 2 * border_width
    local min_x = args.bounding_rect.x
    local min_y = args.bounding_rect.y
    local max_x = min_x + args.bounding_rect.width - width
    local max_y = min_y + args.bounding_rect.height - height

    local x, y

    if args.geometry then
        local paddings = menu.paddings
        local submenu_offset = menu.submenu_offset

        x = args.geometry.x + args.geometry.width + submenu_offset
        if x > max_x then
            x = args.geometry.x - width - submenu_offset
        end
        y = args.geometry.y - paddings.top - border_width
    else
        local coords = args.coords
        x = coords.x
        y = coords.y
    end

    menu.x = x < min_x and min_x or (x > max_x and max_x or x)
    menu.y = y < min_y and min_y or (y > max_y and max_y or y)
end

local function place(menu, args)
    args = args or {}

    local coords = args.coords or capi.mouse.coords()
    local screen = args.screen
        or awful.screen.getbycoord(coords.x, coords.y)
        or capi.mouse.screen
    screen = get_screen(screen)
    local bounds = screen:get_bounding_geometry(menu.placement_bounding_args)

    local border_width = menu.border_width
    local paddings = menu.paddings
    local max_width = bounds.width - 2 * border_width - paddings.left - paddings.right
    local max_height = bounds.height - 2 * border_width - paddings.top - paddings.bottom
    local width, height = menu._private.layout:fit({
        screen = screen,
        dpi = screen.dpi,
        drawable = menu._drawable,
    }, max_width, max_height)

    menu.width = math.max(1, width + paddings.left + paddings.right)
    menu.height = math.max(1, height + paddings.top + paddings.bottom)

    local parent = menu._private.parent
    local placement_args = {
        geometry = parent and parent:get_item_geometry(parent.active_submenu.index),
        coords = coords,
        bounding_rect = bounds,
        screen = screen,
    }

    local placement = args.placement
        or menu.placement
        or default_placement
    placement(menu, placement_args)
end

function mebox:get_active_menu()
    local active = self
    while active._private.active_submenu do
        active = active._private.active_submenu.menu
    end
    return active
end

function mebox:get_root_menu()
    local root = self
    while root._private.parent do
        root = root._private.parent
    end
    return root
end

function mebox:get_item(index)
    local item = index and self._private.items[index]
    local item_widget = item
        and item.index == index
        and item.display_index
        and self._private.layout.children[item.display_index]
    return item, item_widget
end

function mebox:get_item_geometry(index)
    local border_width = self.border_width
    local geometry = self:geometry()
    local _, item_widget = self:get_item(index)
    local item_geometry = item_widget and widget_helper.find_geometry(item_widget, self)
    return item_geometry and {
        x = geometry.x + item_geometry.x + border_width,
        y = geometry.y + item_geometry.y + border_width,
        width = item_geometry.width,
        height = item_geometry.height,
    }
end

local function item_is_active(item)
    return item and item.visible and item.enabled
end

local function get_property_value(property, item, menu)
    if item[property] ~= nil then
        return item[property]
    else
        return menu[property]
    end
end

local function get_item_template(item, menu)
    return item and item.template or menu.item_template
end

local function update_item(item_widget, item, menu)
    if not item or not item_widget then
        return
    end
    local template = get_item_template(item, menu)
    if type(template.update_callback) == "function" then
        template.update_callback(item_widget, item, menu)
    end
end

local function fix_selected_item(menu, keep_selected_index)
    local actual_selected_index

    for index = 1, #menu._private.items do
        local item, item_widget = menu:get_item(index)

        if keep_selected_index then
            item.selected = index == menu._private.selected_index
            if item.selected then
                actual_selected_index = index
            end
        else
            if item.selected then
                if actual_selected_index then
                    item.selected = false
                else
                    actual_selected_index = index
                end
            end
        end

        if item_widget then
            update_item(item_widget, item, menu)
        end
    end

    menu._private.selected_index = actual_selected_index
end

local function attach_active_submenu(menu, submenu, submenu_index)
    assert(not menu._private.active_submenu)
    menu._private.active_submenu = {
        menu = submenu,
        index = submenu_index,
    }
    menu.opacity = menu.inactive_opacity or 1
    menu:unselect()
end

local function detach_active_submenu(menu)
    if menu._private.active_submenu and not menu._private.submenu_cache then
        menu._private.active_submenu.menu._private.parent = nil
    end
    menu._private.active_submenu = nil
    menu.opacity = menu.active_opacity or 1
end

local function hide_active_submenu(menu)
    if menu._private.active_submenu then
        menu._private.active_submenu.menu:hide()
        detach_active_submenu(menu)
    end
end

function mebox:hide_all()
    local root_menu = self:get_root_menu()
    if root_menu then
        root_menu:hide()
    end
end

function mebox:hide(context)
    context = context or {}

    hide_active_submenu(self)

    local parent = self._private.parent
    if parent and parent._private.active_submenu then
        if context.source == "keyboard" or context.select_parent then
            parent:select(parent._private.active_submenu.index)
        end
        detach_active_submenu(parent)
    end

    if self.visible then
        for _, item in ipairs(self._private.items) do
            if type(item.on_hide) == "function" then
                item.on_hide(item, self)
            end
        end

        if type(self._private.on_hide) == "function" then
            self._private.on_hide(self)
        end
    end

    if self._private.keygrabber_auto and self._private.keygrabber then
        self._private.keygrabber:stop()
    end

    self.visible = false

    self._private.layout:reset()
    self._private.items = nil
    self._private.selected_index = nil
end

function mebox:show_submenu(index, context)
    context = context or {}

    if self._private.active_submenu and self._private.active_submenu.index == index then
        if context.source == "mouse" then
            hide_active_submenu(self)
        end
        return
    end

    hide_active_submenu(self)

    index = index or self._private.selected_index
    local item = self:get_item(index)
    if not item_is_active(item) or not item.submenu then
        return
    end

    local submenu = self._private.submenu_cache and self._private.submenu_cache[index]
    if not submenu then
        local submenu_args = type(item.submenu) == "function"
            and item.submenu(self)
            or item.submenu
        submenu = mebox.new(submenu_args, true)
        submenu._private.parent = self
        if self._private.submenu_cache then
            self._private.submenu_cache[index] = submenu
        end
    end

    if not submenu then
        return
    end

    attach_active_submenu(self, submenu, index)

    submenu:show(nil, context)
end

function mebox:show(args, context)
    if self.visible then
        return
    end

    args = args or {}
    context = context or {}

    if type(self._private.on_show) == "function" then
        if self._private.on_show(self, args, context) == false then
            return
        end
    end

    self._private.layout:reset()
    self._private.items = {}

    local display_index = 1
    local items = type(self._private.items_source) == "function"
        and self._private.items_source(self, args, context)
        or self._private.items_source
    for index, item in ipairs(items) do
        if type(item) == "function" then
            item = item(self, args, context)
        end
        self._private.items[index] = item

        item.selected = false

        if type(item.on_show) == "function" then
            if item.on_show(item, self, args, context) == false then
                item.visible = false
            end
        end

        item.visible = item.visible == nil or item.visible ~= false
        item.enabled = item.enabled == nil or item.enabled ~= false
        item.selected = item.selected == nil or item.selected ~= false

        item.index = index
        item.display_index = item.visible and display_index or nil

        if item.visible then
            display_index = display_index + 1

            local item_template = get_item_template(item, self)
            local item_widget = base.make_widget_from_value(item_template)

            local function click_action()
                self:execute(index, { source = "mouse" })
            end

            item_widget.buttons = item.buttons_builder
                and item.buttons_builder(item, self, click_action)
                or binding.awful_buttons {
                    binding.awful({}, btn.left,
                        not item.urgent and click_action,
                        item.urgent and click_action),
                }

            item_widget:connect_signal("mouse::enter", function()
                if get_property_value("mouse_move_select", item, self) then
                    self:select(index)
                end
                if get_property_value("mouse_move_show_submenu", item, self) then
                    self:show_submenu(index)
                else
                    hide_active_submenu(self)
                end
            end)

            self._private.layout:add(item_widget)
        end
    end

    if self._private.keygrabber_auto and self._private.keygrabber then
        self._private.keygrabber:start()
    end

    self._private.selected_index = args.selected_index

    fix_selected_item(self, true)

    if self._private.selected_index == nil and context.source == "keyboard" then
        self:select_by_direction(1)
    end

    place(self, args)

    self.visible = true
end

function mebox:toggle(args, context)
    if self.visible then
        self:hide(context)
        return false
    else
        self:show(args, context)
        return true
    end
end

function mebox:unselect()
    local index = self._private.selected_index

    self._private.selected_index = nil

    local item, item_widget = self:get_item(index)
    if not item then
        return
    end

    item.selected = false

    update_item(item_widget, item, self)
end

function mebox:select(index)
    local item, item_widget = self:get_item(index)
    if not item_is_active(item) then
        return false
    end

    self:unselect()

    self._private.selected_index = index

    item.selected = true

    update_item(item_widget, item, self)

    return true
end

function mebox:execute(index, context)
    index = index or self._private.selected_index
    local item, item_widget = self:get_item(index)
    if not item_is_active(item) then
        return
    end

    context = context or {}

    local done

    local function can_process(action)
        return done == nil
            and item[action]
            and (context.action == nil or context.action == action)
    end

    if can_process("submenu") then
        self:show_submenu(index, context)
        done = false
    end

    if can_process("callback") then
        done = item.callback(item_widget, item, self, context) ~= false
    end

    if done then
        self:hide_all()
    end
end

function mebox:update_item(index)
    local item, item_widget = self:get_item(index)
    update_item(item_widget, item, self)
end

local function sign(value)
    value = tonumber(value)
    if not value or value == 0 then
        return 0
    end
    return value > 0 and 1 or -1
end

function mebox:select_by_direction(direction, seek_origin)
    local count = #self._private.items
    if count < 1 then
        return
    end

    local index
    if type(seek_origin) == "number" then
        index = seek_origin
    elseif seek_origin == "begin" then
        index = 0
    elseif seek_origin == "end" then
        index = count + 1
    else
        index = self._private.selected_index or 0
    end

    direction = sign(direction)
    if direction == 0 then
        return
    end
    for _ = 1, count do
        index = index + direction
        if index < 1 then
            index = count
        elseif index > count then
            index = 1
        end

        if self:select(index) then
            return
        end
    end
end

local function default_layout_navigator(menu, x, y, context)
    if y ~= 0 then
        menu:select_by_direction(y)
    elseif x < 0 then
        menu:hide(context)
    elseif x > 0 then
        menu:execute(nil, context)
    end
end

function mebox:navigate(x, y, context)
    context = context or {}
    local layout_navigator = type(self._private.layout_navigator) == "function"
        and self._private.layout_navigator
        or default_layout_navigator
    layout_navigator(self, sign(x), sign(y), context)
end

noice.define_style_properties(mebox, {
    bg = { proxy = true },
    fg = { proxy = true },
    border_color = { proxy = true },
    border_width = { proxy = true },
    shape = { proxy = true },
    spacing = { id = "#layout", property = "spacing" },
    paddings = { id = "#padding", property = "margins" },
    item_width = {},
    item_height = {},
    item_template = {},
    placement = {},
    placement_bounding_args = {},
    active_opacity = {},
    inactive_opacity = {},
    submenu_offset = {},
    separator_template = {},
    header_template = {},
})

--[[

new_args:
- (style properties)
- layout : widget [wibox.layout.fixed.vertical]
- layout_navigator : function(menu, x, y, navigation_context) [nil]
- cache_submenus : boolean [true]
- items_source : table<item> | function(menu, show_args, show_context) [self]
- on_show : function(menu, show_args, show_context) [nil]
- on_hide : function(menu) [nil]
- mouse_move_select : boolean [false]
- mouse_move_show_submenu : boolean [true]
- keygrabber_auto : boolean [true]
- keygrabber_builder : function(menu) [nil]
- buttons_builder : function(menu) [nil]

menu._private:
- parent : menu | nil
- active_submenu : table | nil
- submenu_cache : table<menu> | nil
- items : table<item> | nil
- selected_index : number | nil
- layout : widget
- layout_navigator : function(menu, x, y, navigation_context) | nil
- items_source : table<item> | function(menu, show_args, show_context)
- on_show : function(menu, show_args, show_context) | nil
- on_hide : function(menu) | nil
- mouse_move_select : boolean
- mouse_move_show_submenu : boolean
- keygrabber_auto : boolean
- keygrabber : awful.keygrabber

item:
- index : number
- display_index : number
- visible : boolean
- enabled : boolean
- selected : boolean
- mouse_move_select : boolean | nil
- mouse_move_show_submenu : boolean | nil
- submenu : ctor_args | nil
- callback : function(item_widget, item, menu, execute_context) | nil
- on_show : function(item, menu, show_args, show_context) | nil
- on_hide : function(item, menu) | nil
- buttons_builder : function(item, menu, default_click_action) [nil]

active_submenu:
- index : number
- menu : menu

]]

function mebox.new(args, is_submenu)
    args = args or {}

    local self = wibox {
        type = "popup_menu",
        ontop = true,
        visible = false,
        widget = {
            id = "#padding",
            layout = wibox.container.margin,
            {
                id = "#layout",
                layout = args.layout or wibox.layout.fixed.vertical,
            },
        },
    }

    gtable.crush(self, mebox, true)

    self._private.submenu_cache = args.cache_submenus ~= false and {} or nil
    self._private.items_source = args.items_source or args
    self._private.on_show = args.on_show
    self._private.on_hide = args.on_hide
    self._private.mouse_move_select = args.mouse_move_select == true
    self._private.mouse_move_show_submenu = args.mouse_move_show_submenu ~= false

    self._private.layout = self:get_children_by_id("#layout")[1]
    self._private.layout_navigator = args.layout_navigator

    noice.initialize_style(self, self.widget, beautiful.mebox.default_style)

    self:apply_style(args)

    self.buttons = type(args.buttons_builder) == "function"
        and args.buttons_builder(self)
        or binding.awful_buttons {
            binding.awful({}, btn.right, function()
                self:hide()
            end),
        }

    if not is_submenu then
        self._private.keygrabber_auto = args.keygrabber_auto ~= false
        self._private.keygrabber = type(args.keygrabber_builder) == "function"
            and args.keygrabber_builder(self)
            or awful.keygrabber {
                keybindings = binding.awful_keys {
                    binding.awful({}, {
                        { trigger = "Left", x = -1 },
                        { trigger = "h", x = -1 },
                        { trigger = "Right", x = 1 },
                        { trigger = "l", x = 1 },
                        { trigger = "Up", y = -1 },
                        { trigger = "k", y = -1 },
                        { trigger = "Down", y = 1 },
                        { trigger = "j", y = 1 },
                    }, function(trigger)
                        local active_menu = self:get_active_menu()
                        active_menu:navigate(trigger.x, trigger.y, { source = "keyboard" })
                    end),
                    binding.awful({}, {
                        { trigger = "Home", direction = 1, seek_origin = "begin" },
                        { trigger = "End", direction = -1, seek_origin = "end" },
                    }, function(trigger)
                        local active_menu = self:get_active_menu()
                        active_menu:select_by_direction(trigger.direction, trigger.seek_origin)
                    end),
                    binding.awful({}, "Tab", function()
                        local active_menu = self:get_active_menu()
                        active_menu:select_by_direction(1)
                    end),
                    binding.awful({ mod.shift }, "Tab", function()
                        local active_menu = self:get_active_menu()
                        active_menu:select_by_direction(-1)
                    end),
                    binding.awful({}, "Return", function()
                        local active_menu = self:get_active_menu()
                        active_menu:execute(nil, { source = "keyboard" })
                    end),
                    binding.awful({ mod.shift }, "Return", function()
                        local active_menu = self:get_active_menu()
                        active_menu:execute(nil, { source = "keyboard", action = "callback" })
                    end),
                    binding.awful({}, "Escape", function()
                        self:hide({ source = "keyboard" })
                    end),
                    binding.awful({ mod.shift }, "Escape", function()
                        local active_menu = self:get_active_menu()
                        active_menu:hide({ source = "keyboard" })
                    end),
                },
            }
    end

    return self
end

function mebox.mt:__call(...)
    return mebox.new(...)
end

return setmetatable(mebox, mebox.mt)