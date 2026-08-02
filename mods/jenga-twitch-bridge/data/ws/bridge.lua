local HOST_URL = "ws://localhost:9090"

local ffi = ffi or _G.ffi or require("ffi")

ffi.cdef[[
struct pollsocket* pollws_open(const char* url);
void pollws_close(struct pollsocket* ctx);
int pollws_status(struct pollsocket* ctx);
void pollws_send(struct pollsocket* ctx, const char* msg);
int pollws_poll(struct pollsocket* ctx);
unsigned int pollws_get(struct pollsocket* ctx, char* dest, unsigned int dest_size);
unsigned int pollws_pop(struct pollsocket* ctx, char* dest, unsigned int dest_size);
]]

local pollws = ffi.load(
    "mods\\jenga-twitch-bridge\\data\\pollws.dll"
)

local socket = pollws.pollws_open(HOST_URL)
local scratch_size = 65536
local scratch = ffi.new(
    "int8_t[?]",
    scratch_size
)

local last_command_serial = ""
local heartbeat_frame = 0

local function send(message)
    if socket == nil then
        return
    end

    pollws.pollws_send(
        socket,
        tostring(message or "")
    )
end

local function receive()
    if socket == nil then
        return nil
    end

    local size = pollws.pollws_pop(
        socket,
        scratch,
        scratch_size
    )

    if size <= 0 then
        return nil
    end

    return ffi.string(
        scratch,
        size
    )
end

local function execute_command(command)
    local fn, error_message =
        loadstring(command)

    if fn == nil then
        print(
            "JENGA Twitch bridge parse error: "
            .. tostring(error_message)
        )

        return
    end

    local ok, runtime_error = pcall(fn)

    if not ok then
        print(
            "JENGA Twitch bridge runtime error: "
            .. tostring(runtime_error)
        )
    end
end

function JengaTwitchBridgeUpdate()
    local incoming = receive()

    while incoming ~= nil do
        execute_command(incoming)
        incoming = receive()
    end

    local serial = GlobalsGetValue(
        "jenga_twitch_command_serial",
        "0"
    )

    if serial ~= last_command_serial then
        last_command_serial = serial

        local command = GlobalsGetValue(
            "jenga_twitch_command",
            ""
        )

        if command ~= "" then
            send(
                "JENGA_COMMAND|"
                .. command
            )
        end
    end

    heartbeat_frame = heartbeat_frame + 1

    if heartbeat_frame >= 60 then
        heartbeat_frame = 0

        send(
            '{"kind":"heartbeat","source":"noita"}'
        )
    end
end
