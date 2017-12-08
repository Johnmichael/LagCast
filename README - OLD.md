This mod is for the WoW Classic (1.12 patch) servers, it will
not work with the pre-Burning Crusade patch or anything after.
The purpose is to emulate the Quartz Castbar mod which displayed
estimated latency, furthermore it intelligently cancels spells
without any further configuration or special macros required.

It is similar in functionality to this mod:
  http://classic-addons.feenixtools.com/Fastcast_v1.11.2.zip

The following major sections exist in this short readme:
  * WHY WOULD I WANT THIS MOD
  * SLASH COMMAND CONFIGURATION
  * MOD-SPECIFIC CONFIGURATION AND USAGE

  
WHY WOULD I WANT THIS MOD

* If you have high ping (200ms+) and want to greatly increase your DPS
 and reduce frustration while levelling and in raids, use this mod.

* If you have moderate ping (70ms+) and want to experiment to see if you
  get a DPS boost in raids.

* If you live next door to the server, congratulations. You probably don't
  need this mod.

* This mod does not benefit from constant interruptions to your cast times
  (ie PvP). It does what it can to compensate for it, but if you're hit 2.95s
  into a 3s cast causing spell pushback and you're mashing away for your
  next spell, prepare for disappointment.


SLASH COMMAND CONFIGURATION

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
    -- Do this if you have non-blizzard castbar mods loaded to get
    -- them back.
    /console reloadui

  Displays the overridden castbar with the lag indicator, but does
  not perform autocancelling:
    /lc bar_only

  If you have 'bar_only' mode set or if you have this mod completely
  disabled, you can still invoke intelligent spellstopcasting like so.
  This is how you would craft an explicit macro, this is more for the
  poweruser who knows what they are doing:
    /script LagCast_StopCasting()
    /cast Fireball
  OR this, which is the equivalent of when you press an action key
    /script LagCast("Fireball")
  OR this for spell ranks
    /script LagCast("Frostbolt(Rank 1)")
  (Remember you will need to disable this mod and possibly reload your UI
   if you're doing that power-user thing)


MOD-SPECIFIC CONFIGURATION AND USAGE

There are two variables which control how lagcast stopcasting operates,
their operation is quite simple. They can be accessed via the command:
  /lagcast config   OR  /lc config

  Minimum Allowable Latency:
    By default this is set to 0 and does nothing. However, sometimes
    you will get a far-lower than expected ping and this could lead
    to your spells getting cancelled. If you know you are always 350ms
    away from the server and for some reason you get a ping of
    220ms, you can "force" this mod to think it's actually 350ms which
    will prevent spell casts being cancelled prematurely.

  Extra Buffer:
    The in-game latency measurement is updated every 30 seconds, however
    in-game latency is more variable than that. It could spike up to
    50ms depending on your ISP, this setting is an extra guard against
    that. If you cast a spell, a cancel operation will go through only
    after this number of milliseconds:
      max('Minimum Allowable Latency', 'In-Game Latency') + 'Extra Buffer'

Here is a time-line of what happens during casting of a 3 second spell,
assume you are spamming the same spell every 20ms, you have a
latency of 400ms and an extra-buffer of 50ms:

Graph legend: 
  '-' - 50ms indicator
  '+' - 500ms indicator
  'c' - ignored spell cast attempt (in this example every 200ms)
  'C' - spell cast attempt sent to server (every 200ms)
  '*' - all cast attempts before this point (2.55s, ie 3s - (400ms + 50ms))
        are ignored. The first cast attempt after this point will have a
        spellstopcasting call issued, and all cast attempts will have a
        spell attempted to be cast
  'S' - a spellstopcasting is issued here
 
        0.5s       1s       1.5s       2s       2.5s       3s
|---------+---------+---------+---------+---------+*S-------|
    c   c   c   c   c   c   c   c   c   c   c   c  *C   C   C
                                                   *  

If the latency is truly 300ms, then here's a toplevel timeframe:
  0 to 2.55s - LagCast will silently discard all spell cast attempts
               before this point
  2.55s - at this point, spell attempts will  not be discarded
  2.60s - spellstop sent to server, new spell sent to server
  2.80s - new spell sent to server (no stopcast)
  3.00s - at this time, we expect the server to have sent a
          SPELLCAST_START event to us. When we get it a new
          castbar will be displayed

