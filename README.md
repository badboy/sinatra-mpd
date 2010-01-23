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
but the mpd.rb can handle this, so change this if you need it.

Then start the server:

    rackup config.ru

and browse the interface at [http://localhost:9292/](http://localhost:9292/)

More:
-----

Just for fun I implemented a version using [mustache][] in the mustache branch.

Copyright:
----------

Copyright (c) 2009 by Jan-Erik Rediger. See LICENSE for details.

mpd.rb is Copyright (c) 2004, Michael C. Libby (mcl@andsoforth.com) (Thanks ;))

[MPD]: http://mpd.wikia.com/wiki/Music_Player_Daemon_Wiki
[Sinatra]: http://www.sinatrarb.com/
[gitsinatra]: http://github.com/sinatra/sinatra/
[mustache]: http://github.com/defunkt/mustache/
