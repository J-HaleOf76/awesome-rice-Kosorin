local ipairs = ipairs
local awful = require("awful")
local capsule = require("widget.capsule")
local wibox = require("wibox")
local binding = require("io.binding")
local mod = binding.modifier
local btn = binding.button
local dpi = dpi
local common = require("awful.widget.common")
local base = require("wibox.widget.base")
local beautiful = require("beautiful")
local gtable = require("gears.table")
local mebox = require("widget.mebox")
local client_menu_template = require("ui.menu.templates.client")
local aplacement = require("awful.placement")
local widget_helper = require("helpers.widget")
local pango = require("utils.pango")


local clientlist = { mt = {} }


function clientlist:show_client_menu(client)
    if not client or not client.valid then
        return
    end
    local item = self._private.cache and self._private.cache[client]
    local container = item and item.container
    if container then
        local menu = self._private.menu
        if not menu then
            menu = mebox(client_menu_template.shared)
            self._private.menu = menu
        end
        local old_client = menu.client
        menu:hide()
        if old_client ~= client then
            menu:show {
                client = client,
                placement = function(menu)
                    aplacement.wibar(menu, {
                        geometry = widget_helper.find_geometry(container, self._private.wibar),
                        position = "bottom",
                        anchor = "middle",
                        honor_workarea = true,
                        honor_padding = false,
                        margins = beautiful.wibar_popup_margin,
                    })
                end,
            }
        end
    end
end

function clientlist.new(wibar)
    local self
    self = awful.widget.tasklist {
        screen = wibar.screen,
        filter = awful.widget.tasklist.filter.currenttags,
        update_function = function(layout, buttons, label, cache, clients, args)
            if not self._private.cache or self._private.cache ~= cache then
                self._private.cache = cache
            end

            layout.widget:reset()
            for index, client in ipairs(clients) do
                local item = cache[client]
                if item and item.buttons ~= buttons then
                    item = nil
                end

                if not item then
                    local root = base.make_widget_from_value(args.widget_template)
                    root.buttons = { common.create_buttons(buttons, client) }
                    root:connect_signal("mouse::enter", function()
                        local menu = self._private.menu
                        if menu and menu.visible and menu.client ~= client then
                            self:show_client_menu(client)
                        end
                    end)

                    item = {
                        buttons = buttons,
                        root = root,
                        container = root:get_children_by_id("#container")[1],
                        icon = root:get_children_by_id("#icon")[1],
                        text = root:get_children_by_id("#text")[1],
                    }
                    cache[client] = item

                    if args and args.create_callback then
                        args.create_callback(item.root, client, index, clients)
                    end
                else
                    if args and args.update_callback then
                        args.update_callback(item.root, client, index, clients)
                    end
                end

                local text, background, _, icon, item_args = label(client, item.text)
                item_args = item_args or {}

                if item.container then
                    item.container.background = background
                    item.container.border_width = item_args.shape_border_width
                    item.container.border_color = item_args.shape_border_color
                end

                if item.text then
                    if not item.text:set_markup_silently(text) then
                        item.text:set_markup(pango.i("&lt;Invalid text&gt;"))
                    end
                end

                icon = icon or (client.desktop_file and client.desktop_file.icon_path)
                if item.icon then
                    if icon then
                        item.icon:set_image(icon)
                    end
                    item.icon.forced_height = item_args.icon_size
                    item.icon.forced_width = item_args.icon_size
                end

                layout.widget:add(item.root)
            end
        end,
        buttons = binding.awful_buttons {
            binding.awful({}, btn.left, function(_, client)
                client:activate { context = "clientlist" }
            end),
            binding.awful({}, btn.right, function(_, client)
                self:show_client_menu(client)
            end),
            binding.awful({}, btn.middle, nil, function(_, client)
                client:kill()
            end),
            binding.awful({}, {
                { trigger = btn.wheel_up, offset = -1 },
                { trigger = btn.wheel_down, offset = 1 },
            }, function(trigger)
                local client = awful.client.next(trigger.offset)
                if client then
                    client:activate { context = "clientlist" }
                end
            end),
        },
        layout = {
            layout = wibox.container.margin,
            left = -beautiful.wibar_spacing / 2,
            right = -beautiful.wibar_spacing / 2,
            {
                layout = wibox.layout.fixed.horizontal,
            },
        },
        widget_template = {
            id = "#container",
            widget = capsule,
            forced_width = dpi(220),
            margins = {
                left = beautiful.wibar_spacing / 2,
                right = beautiful.wibar_spacing / 2,
                top = beautiful.wibar_padding.top,
                bottom = beautiful.wibar_padding.bottom,
            },
            {
                layout = wibox.layout.fixed.horizontal,
                spacing = beautiful.capsule.item_content_spacing,
                {
                    id = "#icon",
                    widget = wibox.widget.imagebox,
                    resize = true,
                },
                {
                    id = "#text",
                    widget = wibox.widget.textbox,
                },
            },
        },
    }

    gtable.crush(self, clientlist, true)

    self._private.wibar = wibar

    return self
end

function clientlist.mt:__call(...)
    return clientlist.new(...)
end

return setmetatable(clientlist, clientlist.mt)