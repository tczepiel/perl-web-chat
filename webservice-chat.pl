#!/usr/bin/env perl
use strict;
use warnings;

use Mojolicious::Lite;
use Mojo::IOLoop;
use Mojo::JSON;
use Scalar::Util qw(refaddr);

my $TIMEOUT = 300;
my $JSON = Mojo::JSON->new();

my %chat;
my %obj2reg_id;
my %conn2nick;

get '/' => 'index';

websocket '/chat' => sub {
    my $self = shift;

    Mojo::IOLoop->stream($self->tx->connection())->timeout($TIMEOUT);

    $self->send($JSON->encode({register => 1}));

    $self->on(message => sub {
        my ($self, $msg ) = @_;

        my $obj = $JSON->decode($msg);

        #notify the others
        if ( exists $obj->{register} && (my $reg_id = $obj->{register}) ) {
            $chat{$reg_id} ||= {};

            $conn2nick{ $self->tx->connection() } = $obj->{name};

            if(my @others = keys %{$chat{$reg_id}}) {

                my $name = $obj->{name};
                for my $other_client (@others) {
                    my $client = $chat{$reg_id}{$other_client};
                    $client->send($JSON->encode({
                        new_user => $name,
                    }));

                    $self->send($JSON->encode({
                        new_user => $conn2nick{ $client->tx->connection() },
                    }));
                }
            }

            $chat{$reg_id}{$self->tx->connection()} = $self;
            $obj2reg_id{refaddr($self)} = $reg_id;
        }
        elsif ( exists $obj->{message} ) {
            my $reg_id = $obj2reg_id{refaddr($self)};
            my @recipients = values %{$chat{$reg_id}};
            for my $recipient (@recipients) {
                $recipient->send($msg);
            }
            
        }
    });

    $self->on(finish => sub {
        my ($self, $code, $reason) = @_;
        my $reg_id = delete $obj2reg_id{refaddr($self)};

        delete $chat{$reg_id}{$self->tx->connection()};
        my $leaving_user = delete $conn2nick{$self->tx->connection()};
        for my $member (values %{ $chat{$reg_id} } ) {
            $member->send($JSON->encode({ name => $leaving_user, message => "[ user left the chat ]"}));
        }
        delete $chat{$reg_id} unless keys %{$chat{$reg_id}};

    });
};

app->start;

__DATA__

@@ index.html.ep
 <!DOCTYPE html>
  <html>
    <head><title>chat</title></head>
    <body>

    <div>
    <textarea id="input" rows=6 cols=50></textarea>
    </div>
    <div id="scratchpad" class="scratchpad">
    </div>

      <script>

        var getQueryParams = function(qs) {
            qs = qs.split("+").join(" ");

            var params = {}, tokens,
                re = /[?&]?([^=]+)=([^&]*)/g;

            while (tokens = re.exec(qs)) {
                params[decodeURIComponent(tokens[1])]
                    = decodeURIComponent(tokens[2]);
            }

            return params;
        };

        var url_for_chat = '<%= url_for('chat')->to_abs %>';
        console.log("connecting to " + url_for_chat);
        var ws = new WebSocket('<%= url_for('chat')->to_abs %>');
        var params = getQueryParams(window.location.search);
        console.log("params " + JSON.stringify(params));

        var userName;
        if ( params.name ) {
            userName = params.name;
        }
        else {
            userName = prompt("enter your user name:") || 'Anonymous';
        }

        var regId    = params.token;

        console.log(JSON.stringify({register: regId, name: userName}));

        // capture enter, send message from textarea
        if (document.layers) {
              document.captureEvents(Event.KEYDOWN);
        }

        document.onkeydown = function (evt) {
          var keyCode = evt ? (evt.which ? evt.which : evt.keyCode) : event.keyCode;
          if (keyCode == 13) { //enter
            // code 27 - escape
            var message = document.getElementById('input');
            ws.send(JSON.stringify({name: userName, message: message.value}));
            console.log("->" + JSON.stringify({name: userName, message: message.value}));
            message.value = "";
            
          } else {
            return true;
          }
        };

        ws.onmessage = function(event) {

            var scratchpad = document.getElementById("scratchpad");
            var message    = JSON.parse(event.data);
            var p = document.createElement('p');

            if ( message.register && message.register === 1 ) {
                console.log("->" + JSON.stringify({register: regId, name: userName}));
                ws.send(JSON.stringify({register: regId, name: userName}));

                p.innerText = "Connection started";
            }
            else if (message.new_user ) {
                p.innerText = message.new_user + " joined the chat";
            }
            else {
                p.innerText = message.name + ": " + message.message;
            }

            scratchpad.insertAdjacentHTML('afterbegin', p.outerHTML);
        };

      </script>
    </body>
  </html>
