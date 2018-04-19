package Shiftboard::Api;
use strict;
use Shiftboard::Memcache;
use Dancer2;
use Digest::SHA1 qw(sha1_hex);
use Dancer2::Core::Error;
use Dancer2::Plugin::Auth::HTTP::Basic::DWIW;

our $VERSION = '0.1';

set serializer => 'JSON';

=head1 NAME

Shiftboard::Api - A class for handling routes

=head1 SYNOPSIS

An example of a post that takes a string which will be split in the 'split' route handler:

C<curl -X POST -u USER:PASS \
http://your_url/split?signature=04e74f3b8cfcf0b502ff701a9b5f0b98ece0d3b4 \
-d '{"string":"split me"}' >

Response:

C<{"odd":["s","l","t","m"], "even":["p","i"," ","e"]}>

An example of a post that takes a string which will be joined in the 'join' route handler:

C<curl -X POST -u USER:PASS \
http://your_url/join?signature=6edd74450aa9206c4ba0b8c009de382a3e91f404 \
-d '{"odd":["s","l","t","m"], "even":["p","i"," ","e"]}'>

Response:

C<{"string":"split me"}>

An example of retrieving the last user repsonse handled in the 'lastResponse' route handler:

C<curl -u USER:PASS http://your_url/lastResponse>

Response:

C<{"string":"split me"}>

=head1 DESCRIPTION

The class will handle POST/GET requests with required parameters and it will return data to the user if their username and password are correct,
the sha1 signature is valid and they have all of the required parameters.

=cut

=head2 /split

The post method handles the 'split' route. It takes a string as a parameter and will return a JSON object containing
an 'odd' and 'even' key with the odd and even characters from the string.

B<Arguments:>

=over

=item C<string>

A required JSON parameter in which the key is 'string' and the value is a string that will be split and returned to the user

=item C<signature>

A required parameter which is an SHA1 signature based on the is a string parameter passed in

=back

=cut
post '/split' => http_basic_auth required => sub {      
    my $string_param = body_parameters->get('string');
    _setErrorResponse({error_code => 422, message => qq|Missing param 'string'|}) if !$string_param;

    my $args = {
        signature => query_parameters->get('signature'),
        require_signature => 1
    };

    ## check the user and their signature and if the user authenticated properly split the string
    _authenticateRequest($args);

    ## predefine the keys in case we only get one letter to split
    my $response = {
        odd => [],
        even => [],
    };
    my @letters = split('', $string_param);

    my $position = 1;
    foreach my $letter (@letters) {
        my $key = ($position % 2 == 0) ? 'even' : 'odd';
        push(@{$response->{$key}}, $letter);
        $position++;
    }

    ## cache result
    my $memd = Shiftboard::Memcache->new();
    my ($username, $password) = _getUsernameAndPassword();
    $memd->setKey({username => $username, response => $response});

    return $response;
};

=head2 /join

The post method handles the 'join' route. It takes a hash with 2 keys which contain arrays of characters as a parameter and will return a JSON object containing
the joined elements from the arrays

B<Arguments:>

=over

=item C<odd>

A required JSON parameter in which the key is 'odd' is an array of characters that will be merged with the 'even' key and returned as a string

=item C<even>

A required JSON parameter in which the key is 'even' is an array of characters that will be merged with the 'odd' key and returned as a string

=item C<signature>

A required parameter which is an SHA1 signature based on the is a string parameter passed in

=back

=cut
post '/join' => http_basic_auth required => sub {
    my $odd = param('odd');
    my $even = param('even');
    _setErrorResponse({error_code => 422, message => qq|Missing param 'odd' or 'even'|}) if !$odd || !$even;

    my $args = {
        signature => query_parameters->get('signature'),
        require_signature => 1
    };

    ## check the user and their signature and if the user authenticates properly join the arrays
    _authenticateRequest($args);
    
    ## set max length
    my $max_length = scalar(@$odd);
    $max_length = (scalar(@$even) > $max_length) ? scalar(@$even) : $max_length;

    my $index = 0;
    my $string = [];
    ## put the string back together
    while($index < $max_length) {
        push(@{$string}, $odd->[$index]);
        push(@{$string}, $even->[$index]) if defined $even->[$index];
        $index++; 
    }

    ## set response
    my $response = {string => join('', @{$string})};

    ## cache result
    my $memd = Shiftboard::Memcache->new();
    my ($username, $password) = _getUsernameAndPassword();
    $memd->setKey({username => $username, response => $response});

    return $response;
};

=head2 /lastResponse

The get method will return the user's last POST response to them via a memcache call

=cut
get '/lastResponse' => http_basic_auth required => sub {
    ## if the user authenticates properly return their last repsonse
    _authenticateRequest();

    my $memd = Shiftboard::Memcache->new();
    my ($username, $password) = _getUsernameAndPassword();
    my $response = $memd->getKey({username => $username});

    return $response;
};

=head2 _getUsernameAndPassword

A method to get the username and password from the curl command

=cut
sub _getUsernameAndPassword {
    my ($username, $password) = http_basic_auth_login;
    return ($username, $password);
}


=head2 _authenticateRequest

A wrapper method to validate the user and sha1 signature

=cut
sub _authenticateRequest {
    my ($args) = @_;

    ## if the user is not valid throw an error
    if(!_userIsValid()) {
        _setErrorResponse({error_code => 401, message => 'Invalid user'});
    }

    ## if the POST signature is not valid throw an error
    if(!_signatureIsValid($args)) {
        _setErrorResponse({error_code => 403, message => 'Your signature is invalid.'});
    }

    return 1;
}

=head2 _userIsValid

A method to validate the user against the Shiftboard API

=cut
sub _userIsValid {
    ## get http user/password from the curl command
    my ($username, $password) = _getUsernameAndPassword();

    ## autheticate user
    ## we should be getting a json result back with a user_id
    my $response = qx|curl 'https://interview-api.shiftboard.com/auth?username=$username&password=$password'|;
    my $decoded_response = decode_json $response if $response;

    ## if we have a valid response and user then pass otherwise fail
    return ($decoded_response && $decoded_response->{user_id}) ? 1 : 0;
}

=head2 _signatureIsValid

The method validates the signature passed in verus one created using the parameters passed in.

B<Arguments:>

=over

=item C<require_signature>

An optional boolean parameter which determines if we should be expecting a signature from the POST

=item C<signature>

An optional parameter which is an SHA1 signature based on the is a string parameter passed in

=back

=cut
sub _signatureIsValid {
    my ($args) = @_;

    my $status = 1;
    my $signature = $args->{signature};
    my $require_signature = $args->{require_signature} || 0;
    
    if($signature) {  
        ## convert the unparsed body to SHA1 to check versus the one passed in
        my $sha1_signature = sha1_hex(request->body);

        $status = $sha1_signature eq $signature ? 1 : 0;
    }
    
    ## we require a signature but didnt get one passed in
    elsif(!$signature && $require_signature) {
        $status = 0;
    }

    return $status;
}

=head2 _setErrorResponse

The method sets the error response for invalid input or users.

B<Arguments:>

=over

=item C<error_code>

An required parameter which sets the error code for our halt repsonse

=item C<message>

An optional parameter which sets the error message for our halt repsonse

=back

=cut
sub _setErrorResponse {
    my ($args) = @_;
    
    my $error_code = $args->{error_code};
    my $error_message = $args->{message} || 'Please try your request again';
    send_error $error_message, $error_code;
}

true;
