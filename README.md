SinatraMPD
==========

small and simple [MPD][] web interface based on [Sinatra].

Requirements:
-------------

* Ruby (of course)
* [MPD][] (of course)
* [Sinatra][gitsinatra]

Usage:
------

Edit sinatra-mpd.rb and change MPD host and port to your local settings.

Note that I did not implemented the requirement for a password, 
but mpd.rb can handle this, so change this if you need it.

Then start the server:

    rackup config.ru

and browse the interface at [http://localhost:9292/](http://localhost:9292/)

I use this interface with an Nokia E71.
With the latest patches (proper highlighting, search function, volume control [24/04/2010])
it is very useful for simple and fast music playing.

More:
-----

Just for fun I implemented a version using [mustache][] in the [mustache][mustache_branch] branch.

There's now an Iphone design, too, using [jQTouch][].
You can find it in the [iphone][] branch.

Because I don't own an Iphone and I don't even want one, I took a screenshot using Chromium:

![iphone design](http://github.com/badboy/sinatra-mpd/raw/iphone/iphone_design.png)

Copyright:
----------

Copyright (c) 2010 by Jan-Erik Rediger. See LICENSE for details.

mpd.rb is Copyright (c) 2004, Michael C. Libby (mcl@andsoforth.com) (Thanks ;))

[MPD]: http://mpd.wikia.com/wiki/Music_Player_Daemon_Wiki
[Sinatra]: http://www.sinatrarb.com/
[gitsinatra]: http://github.com/sinatra/sinatra/
[mustache]: http://github.com/defunkt/mustache/
[mustache_branch]: http://github.com/badboy/sinatra-mpd/tree/mustache
[iphone]: http://github.com/badboy/sinatra-mpd/tree/iphone
[jqtouch]: http://www.jqtouch.com/
