const fs = require("fs")
const path = require("path")
const tmi = require("tmi.js")
const { WebSocketServer } = require("ws")

const ROOT = __dirname
const CONFIG_PATH = path.join(ROOT, "config.json")

if (!fs.existsSync(CONFIG_PATH)) {
    console.error("config.json is missing.")
    console.error("Run setup_and_start.bat.")
    process.exit(1)
}

const configText = fs
    .readFileSync(CONFIG_PATH, "utf8")
    .replace(/^\uFEFF/, "")

const config = JSON.parse(configText)

const channel = String(
    config.channel || ""
)
    .trim()
    .replace(/^#/, "")
    .toLowerCase()

if (!channel || channel === "channel_name_here") {
    console.error(
        "Please enter your Twitch login name in config.json."
    )
    process.exit(1)
}

let gameSocket = null
let activeVote = null

function escapeLua(value) {
    return String(value ?? "")
        .replace(/\\/g, "\\\\")
        .replace(/"/g, '\\"')
        .replace(/\r?\n/g, " ")
}

function sendToGame(code) {
    if (
        !gameSocket
        || gameSocket.readyState !== 1
    ) {
        return false
    }

    gameSocket.send(code)
    return true
}

function setGlobal(name, value) {
    return sendToGame(
        `GlobalsSetValue("${escapeLua(name)}","${escapeLua(value)}")`
    )
}

function publishBridgeConnected(connected) {
    setGlobal(
        "jenga_twitch_bridge_connected",
        connected ? "1" : "0"
    )
}

function publishVote(
    status = "running",
    winner = 0
) {
    if (!activeVote) {
        return
    }

    const remaining = Math.max(
        0,
        Math.ceil(
            (
                activeVote.endsAt
                - Date.now()
            ) / 1000
        )
    )

    setGlobal(
        "jenga_twitch_state_vote_id",
        activeVote.voteId
    )

    setGlobal(
        "jenga_twitch_state_status",
        status
    )

    setGlobal(
        "jenga_twitch_state_remaining",
        String(remaining)
    )

    setGlobal(
        "jenga_twitch_state_votes",
        activeVote.votes.join(",")
    )

    setGlobal(
        "jenga_twitch_state_winner",
        String(winner)
    )
}

function cancelVote(voteId = "") {
    if (!activeVote) {
        return
    }

    if (
        voteId
        && activeVote.voteId !== voteId
    ) {
        return
    }

    clearInterval(activeVote.timer)
    activeVote = null

    console.log("[JENGA] Vote cancelled.")
}

function finishVote() {
    if (!activeVote) {
        return
    }

    const maximum = Math.max(
        ...activeVote.votes
    )

    const tied = []

    activeVote.votes.forEach(
        (value, index) => {
            if (value === maximum) {
                tied.push(index + 1)
            }
        }
    )

    const winner =
        tied[
            Math.floor(
                Math.random()
                * tied.length
            )
        ] || 1

    publishVote(
        "finished",
        winner
    )

    console.log(
        `[JENGA] Vote finished. Winner: ${winner}`
    )

    clearInterval(activeVote.timer)

    const finished = activeVote

    setTimeout(
        () => {
            if (activeVote === finished) {
                activeVote = null
            }
        },
        5000
    )
}

function startVote(
    voteId,
    optionCount,
    duration
) {
    cancelVote()

    activeVote = {
        voteId,
        optionCount,
        votes: Array(optionCount).fill(0),
        userVotes: new Map(),
        endsAt:
            Date.now()
            + duration * 1000,
        timer: null,
    }

    publishVote(
        "running",
        0
    )

    activeVote.timer = setInterval(
        () => {
            if (!activeVote) {
                return
            }

            if (
                Date.now()
                >= activeVote.endsAt
            ) {
                finishVote()
                return
            }

            publishVote(
                "running",
                0
            )
        },
        250
    )

    console.log(
        `[JENGA] Vote started: ${optionCount} options, ${duration}s.`
    )
}

function handleGameMessage(raw) {
    const text = String(raw)

    if (
        text.startsWith(
            "JENGA_COMMAND|START|"
        )
    ) {
        const parts = text.split("|")

        startVote(
            parts[2] || "",
            Math.max(
                1,
                Number(parts[3]) || 1
            ),
            Math.max(
                1,
                Number(parts[4]) || 30
            )
        )

        return
    }

    if (
        text.startsWith(
            "JENGA_COMMAND|CANCEL|"
        )
    ) {
        const parts = text.split("|")
        cancelVote(parts[2] || "")
        return
    }

    try {
        const message = JSON.parse(text)

        if (
            message.kind === "heartbeat"
            && message.source === "noita"
        ) {
            publishBridgeConnected(true)
        }
    }
    catch (_) {
        console.log(
            `[Noita] ${text}`
        )
    }
}

const server = new WebSocketServer({
    host: "127.0.0.1",
    port: 9090,
})

server.on("connection", socket => {
    if (gameSocket) {
        try {
            gameSocket.close()
        }
        catch (_) {}
    }

    gameSocket = socket

    console.log(
        "[Noita] JENGA bridge connected."
    )

    publishBridgeConnected(true)

    socket.on("message", handleGameMessage)

    socket.on("close", () => {
        if (gameSocket === socket) {
            gameSocket = null
        }

        console.log(
            "[Noita] JENGA bridge disconnected."
        )
    })

    socket.on("error", error => {
        console.error(
            "[Noita] WebSocket error:",
            error.message || error
        )
    })
})

const twitch = new tmi.Client({
    options: {
        debug: false,
        skipUpdatingEmotesets: true,
    },
    connection: {
        secure: true,
        reconnect: true,
        reconnectInterval: 30000,
        timeout: 20000,
    },
})

let twitchJoined = false

async function joinConfiguredChannel() {
    const expected = `#${channel}`

    const joined = twitch
        .getChannels()
        .map(value => value.toLowerCase())

    if (joined.includes(expected)) {
        twitchJoined = true

        console.log(
            `[Twitch] Already listening to ${expected}`
        )

        return true
    }

    try {
        await twitch.join(channel)

        twitchJoined = true

        console.log(
            `[Twitch] Listening to ${expected}`
        )

        return true
    }
    catch (error) {
        twitchJoined = false

        console.error(
            `[Twitch] Could not join ${expected}:`,
            error
        )

        return false
    }
}

twitch.on(
    "connected",
    async (address, port) => {
        console.log(
            `[Twitch] Secure IRC connection established: ${address}:${port}`
        )

        await joinConfiguredChannel()
    }
)

twitch.on(
    "join",
    (
        joinedChannel,
        username,
        self
    ) => {
        if (!self) {
            return
        }

        twitchJoined = true

        console.log(
            `[Twitch] Channel joined successfully: ${joinedChannel}`
        )
    }
)

twitch.on(
    "part",
    (
        partedChannel,
        username,
        self
    ) => {
        if (!self) {
            return
        }

        twitchJoined = false

        console.log(
            `[Twitch] Left channel: ${partedChannel}`
        )
    }
)

twitch.on(
    "disconnected",
    reason => {
        twitchJoined = false

        console.log(
            `[Twitch] Disconnected: ${reason}`
        )
    }
)

twitch.on(
    "reconnect",
    () => {
        twitchJoined = false

        console.log(
            "[Twitch] Reconnecting..."
        )
    }
)

twitch.on(
    "message",
    (
        messageChannel,
        userstate,
        message,
        self
    ) => {
        if (
            self
            || !twitchJoined
            || !activeVote
            || Date.now() >= activeVote.endsAt
        ) {
            return
        }

        const normalizedChannel =
            String(messageChannel || "")
                .toLowerCase()

        if (normalizedChannel !== `#${channel}`) {
            return
        }

        const text = String(message).trim()

        if (!/^\d+$/.test(text)) {
            return
        }

        const choice = Number(text)

        if (
            choice < 1
            || choice > activeVote.optionCount
        ) {
            return
        }

        const voter =
            userstate["user-id"]
            || userstate.username
            || userstate["display-name"]
            || "anonymous"

        const previous =
            activeVote.userVotes.get(voter)

        if (previous === choice) {
            return
        }

        if (previous) {
            activeVote.votes[previous - 1] =
                Math.max(
                    0,
                    activeVote.votes[
                        previous - 1
                    ] - 1
                )
        }

        activeVote.userVotes.set(
            voter,
            choice
        )

        activeVote.votes[choice - 1] += 1

        publishVote(
            "running",
            0
        )

        console.log(
            `[Vote] ${userstate["display-name"] || voter}: ${choice}`
        )
    }
)

async function connectTwitch() {
    try {
        await twitch.connect()

        // Some tmi.js versions emit "connected" before the join promise has
        // completed. Ensure a join is attempted explicitly as a fallback.
        if (!twitchJoined) {
            await joinConfiguredChannel()
        }
    }
    catch (error) {
        console.error(
            "[Twitch] Initial connection failed:",
            error
        )

        console.error(
            "[Twitch] The built-in reconnect will keep trying."
        )
    }
}

connectTwitch()

process.on(
    "unhandledRejection",
    reason => {
        console.error(
            "[Connector] Promise error:",
            reason
        )
    }
)

console.log(
    "[JENGA] Standalone connector started."
)

console.log(
    `[JENGA] Configured Twitch channel: #${channel}`
)

console.log(
    "[JENGA] No chaos events or automatic votes are included."
)

console.log(
    "[JENGA] Waiting for Noita on ws://127.0.0.1:9090"
)
