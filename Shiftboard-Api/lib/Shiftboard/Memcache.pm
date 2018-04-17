package Shiftboard::Memcache;

use strict;
use JSON;
use Cache::Memcached;

our $pools = ['127.0.0.1:11211'];

=head1 NAME

Shiftboard::Memcache - A 'very' basic memcache class

=head1 DESCRIPTION

The class will connect to memcache servers and get/set data which will be cached and used to return the last responses to users

=cut
sub new {
    my ($pack, $args) = @_;

    my $self = { };
    bless($self, $pack);

    my $memd = new Cache::Memcached {
      'servers' => $pools,
      'compress_threshold' => 10_000,
    };

    $self->{connection} = $memd;

    return $self;
}

=head2 getKey

The method will pull the stored information for the user

B<Arguments:>

=over

=item C<username>

A required parameter which is the username (key) that our was used to store our data

=back

=cut
sub getKey {
    my ($self, $args) = @_;

    my $username = $args->{username};
    return $self->{connection}->get($username);
}

=head2 setKey

The method will set information for the user which can later be retrieved

B<Arguments:>

=over

=item C<username>

A required parameter which is the username (key) that our was used to store our data

=item C<response>

A required parameter which is the data we want cached

=back

=cut
sub setKey {
    my ($self, $args) = @_;

    my $username = $args->{username};
    my $response = $args->{response} || {};

    $self->{connection}->set($username, $response);
}

return 1;