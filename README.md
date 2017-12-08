# LagCast

This AddOn is for the WoW Classic (1.12 patch) servers, it will
not work with the pre-Burning Crusade patch or anything after.
The purpose is to emulate the Quartz Castbar mod which displayed
estimated latency, furthermore it intelligently cancels spells
without any further configuration or special macros required.

It is similar in functionality to  Namreeb's [Nampower](https://github.com/namreeb/nampower). Comparatively, the benefit of this AddOn is that it lacks the risk of a primitive anti-cheat believing you are attempting to hack or otherwise cheat.




Is this AddOn for me?

* If you have high ping (200ms+) and want to greatly increase your DPS and reduce frustration while leveling and in raids, use this AddOn.

* If you have moderate ping (70ms+) and want to experiment to see if you get a DPS boost in raids.

* This AddOn does not benefit from constant interruptions to your cast times
  (ie PvP). It does what it can to compensate for it, but if you're hit 2.95s
  into a 3s cast causing spell pushback and you're mashing away for your
  next spell, prepare for disappointment.

  If you live next door to the server, lucky you. You probably don't need this.

## The Problem


>There is a design flaw in this version of the client.  A player is not allowed to cast a
second spell until after the client receives word of the completion of the previous spell.
This means that in addition to the cast time, you have to wait for the time it takes a
message to arrive from the server.  For many U.S. based players connected to E.U. based
realms, this can result in approximately a 20% drop in effective DPS.

Consider the following timeline, assuming a latency of 200ms.

* t = 0, the player begins casting fireball (assume a cast time of one second or 1000ms) and spell cast message is sent to the server.  at this time, the client places a lock on itself, preventing the player from requesting another spell cast.
* t = 200, the spell cast message arrives at the server, and the spell cast begins
* t = 1200, the spell cast finishes and a finish message is sent to the client
* t = 1400, the client receives the finish message and removes the lock it had placed 1400ms ago.

In this scenario, a 1000ms spell takes 1400ms to cast. This AddOn intelligently cancels spells without the need for any further configuration or special macros.

## Slash Command Configuration

The configurable slash command is /lagcast (abbreviated also to /lc),
usage is:
  Displays help:
    /lc  OR  /lc help

  Configures LagCast variables, allows the castbar to be moved via a
  GUI:
    /lc config

  Enables, disables lagcast
    /lc enable  OR  /lc disable

  Uses the default blizzard castbar, and when onloading does not
  override hooks (to let you use other castbars like oCB). This
  mode still performs spell autocancelling:
    /lc stop_only
    -- Do this if you have non-blizzard castbar AddOns loaded to get
    -- them back.
    /console reloadui

  Displays the overridden castbar with the lag indicator, but does
  not perform autocancelling:
    /lc bar_only

  If you have 'bar_only' mode set or if you have this AddOn completely
  disabled, you can still invoke intelligent spellstopcasting like so.
  This is how you would craft an explicit macro, this is more for the
  poweruser who knows what they are doing:
    /script LagCast_StopCasting()
    /cast Fireball
  OR this, which is the equivalent of when you press an action key
    /script LagCast("Fireball")
  OR this for spell ranks
    /script LagCast("Frostbolt(Rank 1)")
  (Remember you will need to disable this AddOn and possibly reload your UI
   if you're doing that power-user thing)


## Configuration and Usage

There are two variables which control how lagcast stopcasting operates,
their operation is quite simple. They can be accessed via the command:
  /lagcast config   OR  /lc config

  Minimum Allowable Latency:
    By default this is set to 0 and does nothing. However, sometimes
    you will get a far-lower than expected ping and this could lead
    to your spells getting cancelled. If you know you are always 350ms
    away from the server and for some reason you get a ping of
    220ms, you can "force" LagCast to think it's actually 350ms which
    will prevent spell casts being cancelled prematurely.

  Extra Buffer:
    The in-game latency measurement is updated every 30 seconds, however
    in-game latency is more variable than that. It could spike up to
    50ms depending on your ISP, this setting is an extra guard against
    that. If you cast a spell, a cancel operation will go through only
    after this number of milliseconds:
      max('Minimum Allowable Latency', 'In-Game Latency') + 'Extra Buffer'



### Notes ###

Author of AddOn: Homercles @ Emerald Dream

Design Flaw Explanation: [Namreeb](https://github.com/namreeb/)
