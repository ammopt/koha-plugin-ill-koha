package Koha::Plugin::Org::KC::ILL::Koha::Api;

use Modern::Perl;
use strict;
use warnings;

use JSON         qw( decode_json encode_json );
use URI::Escape  qw ( uri_unescape );
use MIME::Base64 qw( decode_base64 );

use Mojo::Base 'Mojolicious::Controller';
use Koha::Illbackends::Koha::Base;
use Koha::Plugin::Org::KC::ILL::Koha;

sub Backend_Availability {
    my $c = shift->openapi->valid_input or return;

    my $metadata = $c->validation->param('metadata') || '';
    $metadata = decode_json( decode_base64( uri_unescape($metadata) ) );
    my $backend = Koha::Illbackends::Koha::Base->new;
    my $search = {
        biblionumber  => 0,    # required by C4::Breeding::Z3950Search
        page          => 1,
        id            => [ map { $backend->{targets}->{$_}->{ZID} } keys %{ $backend->{targets} } ],
        isbn          => $metadata->{isbn},
        issn          => $metadata->{issn},
        title         => $metadata->{title},
        author        => $metadata->{author},
        dewey         => $metadata->{dewey},
        subject       => $metadata->{subject},
        lccall        => $metadata->{lccall},
        controlnumber => $metadata->{controlnumber},
        stdid         => $metadata->{stdid},
        srchany       => $metadata->{srchany},
    };

    if ( (!$metadata->{issn} && !$metadata->{isbn}) && !$metadata->{title} ) {
        return $c->render(
            status  => 404,
            openapi => {
                error => 'Missing title or issn/isbn',
            }
        );
    }

    my $results = $backend->_search($search);
    my %seen;
    my @unique_servers = grep { ! $seen{$_}++ } map { $_->{server} } @{ $results->{results} };
    if (@unique_servers) {
        return $c->render(
            status  => 200,
            openapi => {
                # response => $response,
                success  => "Found in " . join(', ', @unique_servers),
            }
        );
    }

    return $c->render(
        status  => 404,
        openapi => {
            error => 'Not found',
        }
    );
}

1;
