#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";


# use this block if you don't need middleware, and only have a single target Dancer app to run here
use Shiftboard::Api;

Shiftboard::Api->to_app;

=begin comment
# use this block if you want to include middleware such as Plack::Middleware::Deflater

use Shiftboard::Api;
use Plack::Builder;

builder {
    enable 'Deflater';
    Shiftboard::Api->to_app;
}

=end comment

=cut

=begin comment
# use this block if you want to mount several applications on different path

use Shiftboard::Api;
use Shiftboard::Api_admin;

use Plack::Builder;

builder {
    mount '/'      => Shiftboard::Api->to_app;
    mount '/admin'      => Shiftboard::Api_admin->to_app;
}

=end comment

=cut

