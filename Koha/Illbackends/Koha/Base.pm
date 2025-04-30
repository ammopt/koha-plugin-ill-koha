package Koha::Illbackends::Koha::Base;

# Copyright 2017 Alex Sassmannshausen <alex.sassmannshausen@gmail.com>
# Copyright 2018 Martin Renvoize <martin.renvoize@ptfs-europe.com>
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;
use DateTime;
use JSON qw( encode_json decode_json );
use HTTP::Request::Common;
use Koha::ILL::Request::Attribute;
use Koha::Patrons;
use LWP::UserAgent;
use File::Basename qw( dirname );
use MIME::Base64 qw( decode_base64 encode_base64 );
use POSIX qw ( floor );
use URI;
use URI::Escape;
use Try::Tiny;

use Koha::I18N qw(__);
use Koha::Plugin::Org::KC::ILL::Koha;

# Modules imminently being deprecated
use C4::Biblio qw( AddBiblio );
use C4::Breeding qw( Z3950Search );
use C4::ImportBatch qw( GetImportRecordMarc );
use C4::Letters;

=head1 NAME

Koha::Illrequest::Backend::Koha - Koha to Koha ILL Backend

=head1 SYNOPSIS

Koha ILL implementation for the SRU + ILS-DI backend

=head1 DESCRIPTION

=head2 Overview

We will be providing the Abstract interface which requires we implement the
following methods:
- create        -> initial placement of the request for an ILL order
- confirm       -> confirm placement of the ILL order
- renew         -> request a currently borrowed ILL be renewed in the backend
- cancel        -> request an already 'confirm'ed ILL order be cancelled
- status        -> request the current status of a confirmed ILL order
- status_graph  -> return a hashref of additional statuses

Each of the above methods will receive the following parameter from
Illrequest.pm:

  {
    request => $request,
    other   => $other,
  }

where:

- $REQUEST is the Illrequest object in Koha.  It's associated
  Illrequestattributes can be accessed through the `illrequestattributes`
  method.
- $OTHER is any further data, generally provided through templates .INCs

Each of the above methods should return a hashref of the following format:

  return {
    error   => 0,
    # ^------- 0|1 to indicate an error
    status  => 'result_code',
    # ^------- Summary of the result of the operation
    message => 'Human readable message.',
    # ^------- Message, possibly to be displayed
    #          Normally messages are derived from status in INCLUDE.
    #          But can be used to pass API messages to the INCLUDE.
    method  => 'status',
    # ^------- Name of the current method invoked.
    #          Used to load the appropriate INCLUDE.
    stage   => 'commit',
    # ^------- The current stage of this method
    #          Used by INCLUDE to determine HTML to generate.
    #          'commit' will result in final processing by Illrequest.pm.
    next    => 'illview'|'illlist',
    # ^------- When stage is 'commit', should we move on to ILLVIEW the
    #          current request or ILLLIST all requests.
    value   => {},
    # ^------- A hashref containing an arbitrary return value that this
    #          backend wants to supply to its INCLUDE.
  };

=head2 On the Koha backend

The Koha backend uses Koha's SRU server to perform searches against other
instances, and it's ILS-DI API to 'confirm' ill requests.

The backend has the notion of targets, each of which is a Koha instance
definition consisting of
  {
    $name => {
      ZID => 'id_of_koha_z_target',
      ILSDI => 'ilsdi_base_uri',
      user => 'remote_user_name',
      password => 'remote_password',
    },
  }

=head1 API

=head2 Class Methods

=cut

=head3 new

  my $backend = Koha::Illrequest::Backend::Koha->new;

=cut

sub new {

  # -> instantiate the backend
  my ($class, $params) = @_;

  my $plugin = Koha::Plugin::Org::KC::ILL::Koha->new;

  # TODO: Check configuration sanity and bailout if required
  my $configuration = $plugin->configuration;
  my $targets   = $configuration->{targets};
  my $framework = (defined $configuration->{framework}) ? $configuration->{framework} : 'ILL';

  my $self = {
    targets   => $targets,
    framework => $framework,
    plugin    => $plugin
  };
  bless($self, $class);
  return $self;
}

sub name {
  return "Koha";
}

=head3 metadata

Return a hashref containing canonical values from the key/value
illrequestattributes store.

=cut

sub metadata {
    my ( $self, $request ) = @_;
    my $attrs                    = $request->extended_attributes;
    my $id                       = scalar $attrs->find( { type => 'bib_id' } );
    my $title                    = scalar $attrs->find( { type => 'title' } );
    my $article_title            = scalar $attrs->find( { type => 'article_title' } );
    my $author                   = scalar $attrs->find( { type => 'author' } );
    my $target                   = scalar $attrs->find( { type => 'target' } );
    my $target_item_id           = scalar $attrs->find( { type => 'target_item_id' } );
    my $target_library_id        = scalar $attrs->find( { type => 'target_library_id' } );
    my $target_library_email     = scalar $attrs->find( { type => 'target_library_email' } );
    my $target_library_name      = scalar $attrs->find( { type => 'target_library_name' } );
    my $isbn                     = scalar $attrs->find( { type => 'isbn' } );
    my $issn                     = scalar $attrs->find( { type => 'issn' } );
    my $doi                      = scalar $attrs->find( { type => 'doi' } );
    my $year                     = scalar $attrs->find( { type => 'year' } );
    my $previous_requested_items = scalar $attrs->find( { type => 'previous_requested_items' } );

    return {
        ID                         => $id                       ? $id->value                       : undef,
        Title                      => $title                    ? $title->value                    : undef,
        "Article Title"            => $article_title            ? $article_title->value            : undef,
        Author                     => $author                   ? $author->value                   : undef,
        ISBN                       => $isbn                     ? $isbn->value                     : undef,
        ISSN                       => $issn                     ? $issn->value                     : undef,
        DOI                        => $doi                      ? $doi->value                      : undef,
        Target                     => $target                   ? $target->value                   : undef,
        "Target Item ID"           => $target_item_id           ? $target_item_id->value           : undef,
        "Target Library ID"        => $target_library_id        ? $target_library_id->value        : undef,
        "Target Library Email"     => $target_library_email     ? $target_library_email->value     : undef,
        "Target Library Name"      => $target_library_name      ? $target_library_name->value      : undef,
        Year                       => $year                     ? $year->value                   : undef,
        "Previous requested items" => $previous_requested_items ? $previous_requested_items->value : undef
    };
}

=head3 capabilities

$capability = $backend->capabilities($name);

Return the sub implementing a capability selected by NAME, or 0 if that
capability is not implemented.

=cut

sub capabilities {
  my ($self, $name) = @_;
  my $capabilities = {

    # We don't implement unmediated for now
    # unmediated_ill => sub { $self->confirm(@_); }

    provides_backend_availability_check => sub { return 1; },

    opac_unauthenticated_ill_requests => sub { return 1; },

    migrate => sub { $self->migrate(@_); }
  };
  return $capabilities->{$name};
}

=head3 status_graph

=cut

sub status_graph {
  return {
    NEW => {
      prev_actions => [ ],
      id             => 'NEW',
      name           => __('New request'),
      ui_method_name => __('New request'),
      method         => 'create',
      next_actions   => [ 'REQ', 'KILL', 'MIG' ],
      ui_method_icon => 'fa-plus',
    },
    REQREV => {
        prev_actions   => [ 'REQ' ],
        id             => 'REQREV',
        name           => __('Request reverted'),
        ui_method_name => __('Revert request'),
        method         => 'cancel',
        next_actions   => [ 'REQ', 'KILL', 'MIG' ],
        ui_method_icon => 'fa-times',
    },
    GENREQ => {
        prev_actions   => [],
        id             => 'GENREQ',
        name           => __('Requested from partners'),
        ui_method_name => __('Place request with partners'),
        method         => 0,
        next_actions   => [],
        ui_method_icon => 'fa-paper-plane',
    },
    CHK => {
        prev_actions   => [ 'REQ', 'COMP' ],
        id             => 'CHK',
        name           => __('Checked out'),
        ui_method_name => __('Check out'),
        needs_prefs    => [ 'CirculateILL' ],
        needs_perms    => [ 'user_circulate_circulate_remaining_permissions' ],
        # An array of functions that all must return true
        needs_all      => [ sub { my $r = shift;  return $r->biblio; } ],
        method         => 'check_out',
        next_actions   => [ ],
        ui_method_icon => 'fa-upload',
    },
    MIG => {
      prev_actions   => ['NEW', 'REQREV', 'QUEUED',],
      id             => 'MIG',
      name           => 'Switched provider',
      ui_method_name => 'Switch provider',
      method         => 'migrate',
      next_actions   => [],
      ui_method_icon => 'fa-search',
    },
    UNAUTH => {
        prev_actions   => [],
        id             => 'UNAUTH',
        name           => 'Unauthenticated',
        ui_method_name => 0,
        method         => 0,
        next_actions   => [ 'REQ', 'MIG', 'KILL' ],
        ui_method_icon => 0,
    }
  };
}

=head3 create

  my $response = $backend->create({
  request    => $requestdetails,
  other      => $other,
  });

This is the initial creation of the request.  We search our Koha targets using
Catmandu's SRU library, and provide a choice from the results from all
targets.

We provide no paging and only rudimentary branch & borrower validation.

=cut

sub create {

  # -> initial placement of the request for an ILL order
  my ($self, $params) = @_;
  my $other = $params->{other};

  my $stage = $other->{stage};

  my $unauthenticated_request =
      C4::Context->preference("ILLOpacUnauthenticatedRequest") && !$other->{'cardnumber'} && $other->{opac};

  if (!$stage || $stage eq 'init') {

    # We simply need our template .INC to produce a search form.
    return {
      error   => 0,
      status  => '',
      message => '',
      method  => 'create',
      stage   => 'search_form',
      value   => $params,
    };
  }
  elsif ($stage eq 'search_form' || $stage eq 'form') {

    # Received search query in 'other'; perform search...
    my $result = {
      status  => "",
      message => "",
      error   => 1,
      value   => {},
      method  => "create",
      stage   => "init",
    };
    my $failed = 0;
    my ( $brw_count, $brw );
    if ($unauthenticated_request) {
        ( $failed, $result ) = _validate_form_params( $other, $result, $params );
        return $result if $failed;
        my $unauth_request_error = Koha::ILL::Request::unauth_request_data_error($other);
        if ( $unauth_request_error ) {
            $result->{status} = "missing_unauth_data";
            $result->{value}  = $params;
            $failed           = 1;
        }
    } else {
        ( $failed, $result ) = _validate_form_params( $other, $result, $params );

        ( $brw_count, $brw ) =
            _validate_borrower( $other->{'cardnumber'} );

        if ( $brw_count == 0 ) {
            $result->{status} = "invalid_borrower";
            $result->{value}  = $params;
            $failed           = 1;
        } elsif ( $brw_count > 1 ) {

            # We must select a specific borrower out of our options.
            $params->{brw}   = $brw;
            $result->{value} = $params;
            $result->{stage} = "borrowers";
            $result->{error} = 0;
            $failed          = 1;
        }
    }

    return $result if $failed;
    # Perform the search
    my $search = {
      biblionumber => 0,    # required by C4::Breeding::Z3950Search
      page => $other->{page} ? $other->{page} : 1,
      id => [map { $self->{targets}->{$_}->{ZID} } keys %{$self->{targets}}],
      isbn          => $other->{isbn},
      issn          => $other->{issn},
      title         => $other->{title},
      author        => $other->{author},
      dewey         => $other->{dewey},
      subject       => $other->{subject},
      lccall        => $other->{lccall},
      controlnumber => $other->{controlnumber},
      stdid         => $other->{stdid},
      srchany       => $other->{srchany},
    };
    my $results = $self->_search($search, $other);

    # Construct the response
    my $response = {
      cwd            => dirname(__FILE__),
      status         => 200,
      message        => "",
      error          => 0,
      value          => $results,
      method         => 'create',
      stage          => 'search_results',
      borrowernumber => $brw ? $brw->borrowernumber : '',
      cardnumber     => $other->{cardnumber},
      branchcode     => $other->{branchcode},
      backend        => $other->{backend},
      query          => $search,
      params         => $params
    };
    return $response;

  }
  elsif ($stage eq 'search_results') {
    my $other = $params->{other};

    my ($biblionumber, $remote_id)
      = $self->_add_from_breeding($other->{breedingid}, $self->{framework}) if $other->{breedingid};

    $remote_id //= $other->{remote_biblio_id} // '';

    my $request_details = _get_request_details($other, $remote_id);

    # ...Populate Illrequest
    my $request = $params->{request};
    $request->borrowernumber($other->{borrowernumber});
    $request->branchcode($other->{branchcode});
    $request->status( $unauthenticated_request ? 'UNAUTH' : 'NEW');
    $request->backend($other->{backend});
    $request->placed(DateTime->now);
    $request->updated(DateTime->now);
    $request->biblio_id($biblionumber) if $other->{breedingid};
    $request->store;

    # ...Populate Illrequestattributes
    while (my ($type, $value) = each %{$request_details}) {
      Koha::ILL::Request::Attribute->new({
        illrequest_id => $request->illrequest_id,
        type          => $type,
        value         => $value,
      })->store if defined $value;
    }
    $request->add_unauthenticated_data( $params->{other} ) if $unauthenticated_request;

    # -> create response.
    return {
      error   => 0,
      status  => '',
      message => '',
      method  => 'create',
      stage   => 'commit',
      next    => 'illview',
      value   => $request_details,
    };
  }
  else {
    # Invalid stage, return error.
    return {
      error   => 1,
      status  => 'unknown_stage',
      message => '',
      method  => 'create',
      stage   => $params->{stage},
      value   => {},
    };
  }
}

=head3 migrate

Migrate a request into or out of this backend.

=cut

sub migrate {
  my ($self, $params) = @_;
  my $other = $params->{other};

  my $stage = $other->{stage};
  my $step  = $other->{step};

  # Recieve a new request from another backend and suppliment it with
  # anything we require speficifcally for this backend.
  if (!$stage || $stage eq 'immigrate') {

    # Fetch original request details
    my $original_request = Koha::ILL::Requests->find($other->{illrequest_id});

    # Initiate immigration search
    if (!$step || $step eq 'init') {

      # Initiate search with details from last request
      my $search = {
        biblionumber => 0,    # required by C4::Breeding::Z3950Search
        page => $other->{page} ? $other->{page} : 1,
        id => [map { $self->{targets}->{$_}->{ZID} } keys %{$self->{targets}}],
      };
      my @recognised_attributes
        = (
        qw/isbn issn title author dewey subject lccall controlnumber stdid srchany/
        );
      my $original_attributes =
          $original_request->extended_attributes->search( { type => { '-in' => \@recognised_attributes } } );
      my $search_attributes
        = {map { $_->type => $_->value } ($original_attributes->as_list)};
      $search = {%{$search}, %{$search_attributes}};

      # Perform a search
      my $results = $self->_search($search, $other);

      my $previous_requested_items = $original_request->extended_attributes->find( { type => 'previous_requested_items' } );
      my $current_item             = $original_request->extended_attributes->find( { type => 'target_item_id' } );

      my @previous_requested_items_array = $previous_requested_items && $previous_requested_items->value ? split( /\|/, $previous_requested_items->value ) : ();

      # Construct the response
      my $response = {
        cwd           => dirname(__FILE__),
        status        => 200,
        message       => "",
        error         => 0,
        value         => $results,
        method        => 'migrate',
        stage         => 'immigrate',
        step          => 'search_results',
        illrequest_id => $other->{illrequest_id},
        backend       => $self->name,
        previous_requested_items => \@previous_requested_items_array,
        ( $current_item ? ( current_item => $current_item->value ) : () ),
        query         => $search,
        params        => $params
      };
      return $response;
    }

    # Import from search results
    elsif ($step eq 'search_results') {
      my ($biblionumber, $remote_id)
        = $self->_add_from_breeding($other->{breedingid}, $self->{framework}) if $other->{breedingid};

      $remote_id //= $other->{remote_biblio_id} // '';

      my $new_request = $params->{request};
      $new_request->borrowernumber($original_request->borrowernumber);
      $new_request->branchcode($original_request->branchcode);
      $new_request->status('NEW');
      $new_request->backend($self->name);
      $new_request->placed(DateTime->now);
      $new_request->updated(DateTime->now);
      $new_request->biblio_id($biblionumber);
      $new_request->store;

      my $request_details = _get_request_details( $other, $remote_id );

      if ( $other->{target_item_id} ) {
        $request_details->{target_item_id} = $other->{target_item_id};

          my $bib_id_attr = $new_request->extended_attributes->find( { type => 'bib_id' } );
          $bib_id_attr->delete if $bib_id_attr;
          my $target_item_id_attr = $new_request->extended_attributes->find( { type => 'target_item_id' } );
          $target_item_id_attr->delete if $target_item_id_attr;
          my $target_library_id_attr = $new_request->extended_attributes->find( { type => 'target_library_id' } );
          $target_library_id_attr->delete if $target_library_id_attr;
          my $target_library_name_attr = $new_request->extended_attributes->find( { type => 'target_library_name' } );
          $target_library_name_attr->delete if $target_library_name_attr;
          my $target_library_email = $new_request->extended_attributes->find( { type => 'target_library_email' } );
          $target_library_email->delete if $target_library_email;
      }

      $request_details->{migrated_from} = $original_request->illrequest_id;

      while (my ($type, $value) = each %{$request_details}) {
        eval {
          Koha::ILL::Request::Attribute->new(
              {
                  illrequest_id => $new_request->illrequest_id,
                  type          => $type,
                  value         => $value,
              }
          )->store if defined $value;
        };
        if ($@) {
          warn "Error adding attribute: $@";
        }
      }

      return {
        error   => 0,
        status  => '',
        message => '',
        method  => 'migrate',
        stage   => 'commit',
        next    => 'emigrate',
        value   => $params,
      };
    }
  }

  # Cleanup any outstanding work and close the request.
  elsif ($stage eq 'emigrate') {
    my $new_request = $params->{request};
    my $from_id = $new_request->extended_attributes->find(
        { type => 'migrated_from' } )->value;
    my $request     = Koha::ILL::Requests->find($from_id);

    clean_up_request($request);

    # Clean up the temporary bib record for the migrated request
    #if ( my $biblio = $request->biblio ) {
    #    DeleteBiblio( $biblio->biblionumber );
    #}

    return {
      error   => 0,
      status  => '',
      message => '',
      method  => 'migrate',
      stage   => 'commit',
      next    => 'illview',
      value   => $params,
    };
  }
}

sub clean_up_request {
    my ($request) = @_;

    $request->status("REQREV");
    $request->orderid(undef);
    $request->store;
}

=head3 confirm

  my $response = $backend->confirm({
    request => $requestdetails,
    other   => $other,
  });

Confirm the placement of the previously "selected" request (by using the
'create' method).

In this case we will generally use $request.
This will be supplied at all times through Illrequest.  $other may be supplied
using templates.

=cut

sub confirm {

  # -> confirm placement of the ILL order
  my ($self, $params) = @_;
  my $stage = $params->{other}->{stage};

  # Turn Illrequestattributes into a plain hashref
  my $value      = {};
  my $attributes = $params->{request}->extended_attributes;
  foreach my $attr (@{$attributes->as_list}) {
    $value->{$attr->type} = $attr->value;
  }
  my $target      = $self->{targets}->{ $value->{target} };
  if ( $target->{rest_api_endpoint} ) {

      my $request = $params->{request};
      if ( !$stage || $stage eq 'init' ) {
        my $url       = URI->new( $target->{rest_api_endpoint}.'/api/v1/libraries/'.$value->{target_library_id} );
        my $encoded_login = encode_base64( $target->{user} . ':' . $target->{password} );
        my $headers   = {
            'Accept'        => 'application/json',
            'Authorization' => "Basic $encoded_login"
        };
        my $rsp = $self->_request( { method => 'GET', url => $url, headers => $headers } );
        my $library_details = decode_json( $rsp );
        my $target_library_email = $library_details->{illemail} || $library_details->{email};
        return _return_template_error( 'Required target library email not found.', $value )
            unless $target_library_email;

        eval {
          Koha::ILL::Request::Attribute->new({
            illrequest_id => $request->illrequest_id,
            type          => 'target_library_email',
            value         => $target_library_email,
          })->store;
        };
        if ($@) {
            warn "Error adding attribute: $@";
        }
        $value->{target_library_email} = $target_library_email;

        return {
            method   => 'confirm',
            stage    => 'confirm',
            value    => $value
        };
      } elsif ( $stage eq 'confirm' ) {
          my $letter_code = 'ILL_PARTNER_REQ';      #TODO: Grab this from config.
          my $letter      = $request->get_notice(
              {
                  notice_code => $letter_code,
                  transport   => 'email'
              }
          );
          return _return_template_error( "Configured letter code not found: $letter_code", $value ) unless $letter;

          my $target_library_email = $request->extended_attributes->find( { type => 'target_library_email' } );
          return _return_template_error( 'Required target library email not found.', $value )
              unless $target_library_email;

          my $from_address = Koha::Libraries->find( $request->branchcode )->branchillemail
              || Koha::Libraries->find( $request->branchcode )->branchemail;
          return _return_template_error( "Required destination library ("
                  . Koha::Libraries->find( $request->branchcode )->branchname
                  . ") ILL email or library email not found.", $value )
              unless $from_address;

          my $enqueue_letter = C4::Letters::EnqueueLetter(
              {
                  letter                 => $letter,
                  from_address           => $from_address,
                  reply_address          => $from_address,
                  to_address             => $target_library_email->value,
                  message_transport_type => 'email',
              }
          );
          return _return_template_error( "Failed to send email: $enqueue_letter", $value )
                unless $enqueue_letter;

          my $logger = Koha::ILL::Request::Logger->new;
          $logger->log_patron_notice(
              {
                  request     => $request,
                  notice_code => $letter_code
              }
          );

          my $current_item = $request->extended_attributes->find( { type => 'target_item_id' } );
          my $previous_requested_items_string;

          my $previous_requested_items = $request->extended_attributes->find( { type => 'previous_requested_items' } );

          if (   $previous_requested_items
              && $previous_requested_items->value
              && $current_item
              && $current_item->value )
          {
              my @previous_requested_items_array = split( /\|/, $previous_requested_items->value );

              unless ( grep { $_ eq $current_item->value } @previous_requested_items_array ) {
                  push @previous_requested_items_array, $current_item->value;
              }
              my $string = join "|", @previous_requested_items_array;

              $previous_requested_items_string = $string;
          } else {
              $previous_requested_items_string = $current_item->value;
          }

          my $previous_requested_items_attr =
              $request->extended_attributes->find( { type => 'previous_requested_items' } );
          $previous_requested_items_attr->delete if $previous_requested_items_attr;

          eval {
              Koha::ILL::Request::Attribute->new(
                  {
                      illrequest_id => $request->illrequest_id,
                      type          => 'previous_requested_items',
                      value         => $previous_requested_items_string,
                  }
                  )->store
                  if defined $previous_requested_items_string;
          };
          if ($@) {
              warn "Error adding attribute: $@";
          }

          my $target_item_id = $request->extended_attributes->find( { type => 'target_item_id' } );
          $request->orderid( $target_item_id->value ) if $target_item_id;
          $request->status("REQ");
          $request->store;

          return {
              error   => 0,
              status  => '',
              message => '',
              method  => 'confirm',
              stage   => 'commit',
              next    => 'illview',
              value   => $value,
          };
      }
  }

  # Submit request to backend...

  # Authentication:
  my $url       = URI->new($target->{ILSDI});
  my $key_pairs = {
    'service'  => 'AuthenticatePatron',
    'username' => $target->{user},
    'password' => $target->{password},
  };
  $url->query_form($key_pairs);
  my $rsp = $self->_request({method => 'GET', url => $url});

  # Catch LWP Errors
  if ($self->{error}) {
    return {
      error   => 1,
      status  => '',
      message => "ILDI Service Error: Request - $url, "
        . "Status - $self->{error}->{status}, "
        . "Content - $self->{error}->{content}, $url",
      method => 'confirm',
      stage  => 'confirm',
      next   => '',
      value  => $value
    };
  }

  my $doc = XML::LibXML->load_xml(string => $rsp);

  # Catch AuthenticatePatron Errors
  my $code_query = "//AuthenticatePatron/code/text()";
  my $code
    = $doc->findnodes($code_query)
    ? ${$doc->findnodes($code_query)}[0]->data
    : undef;
  return {
    error   => 1,
    status  => '',
    message => "Service Authentication Error: $code",
    method  => 'confirm',
    stage   => 'confirm',
    next    => '',
    value   => $value
    }
    if defined($code);

  # Stash the authenticated service user id
  my $id_query = "//AuthenticatePatron/id/text()";
  my $id       = ${$doc->findnodes($id_query)}[0]->data;

  # Place the request
  $url       = URI->new($target->{ILSDI});
  $key_pairs = {
    'service'          => 'HoldTitle',
    'patron_id'        => $id,
    'bib_id'           => $value->{bib_id},
    'request_location' => '127.0.0.1',
  };
  $url->query_form($key_pairs);
  $rsp = $self->_request({method => 'GET', url => $url});

  # Catch LWP Errors
  if ($self->{error}) {
    return {
      error   => 1,
      status  => '',
      message => "ILDI Service Error: Request - $url, "
        . "Status - $self->{error}->{status}, "
        . "Content - $self->{error}->{content}, $url",
      method => 'confirm',
      stage  => 'confirm',
      next   => '',
      value  => $value
    };
  }

  $doc = XML::LibXML->load_xml(string => $rsp);

  # Catch HoldTitle Errors
  $code_query = "//HoldTitle/code/text()";
  $code
    = $doc->findnodes($code_query)
    ? ${$doc->findnodes($code_query)}[0]->data
    : undef;
  return {
    error   => 1,
    status  => '',
    message => "Service Request Error: $code",
    method  => 'confirm',
    stage   => 'confirm',
    next    => '',
    value   => $value
    }
    if defined($code);

  # Stash the hold request response
  my $pickup_query = "//HoldTitle/pickup_location/text()";
  die("Placing hold failed:", $rsp) if !${$doc->findnodes($pickup_query)}[0];

  my $request = $params->{request};
  $request->cost("0 GBP");
  $request->orderid($value->{bib_id});
  $request->status("REQ");
  $request->store;

  # ...then return our result:
  return {
    error   => 0,
    status  => '',
    message => '',
    method  => 'confirm',
    stage   => 'commit',
    next    => 'illview',
    value   => $value,
  };
}

=head3 renew

  my $response = $backend->renew({
  request    => $requestdetails,
  other      => $other,
  });

Attempt to renew a request that was supplied through backend and is currently
in use by us.

We will generally use $request.  This will be supplied at all times through
Illrequest.  $other may be supplied using templates.

=cut

sub renew {

  # -> request a currently borrowed ILL be renewed in the backend
  my ($self, $params) = @_;
  return {
    error   => 1,
    status  => 404,
    message => "Not Implemented",
    method  => 'renew',
    stage   => 'fake',
    value   => {},
  };
}

=head3 cancel

  my $response = $backend->cancel({
    request => $requestdetails,
    other   => $other,
  });

We will attempt to cancel a request that was confirmed.

We will generally use $request.  This will be supplied at all times through
Illrequest.  $other may be supplied using templates.

=cut

sub cancel {
    my ( $self, $params ) = @_;
    my $stage = $params->{other}->{stage};

    if ( !$stage || $stage eq 'init' ) {
        return {
            method => 'cancel',
            stage  => 'confirm',
            value  => $params,
        };
    } elsif ( $stage eq 'confirm' ) {
        my $request = Koha::ILL::Requests->find( $params->{other}->{illrequest_id} );

        clean_up_request($request);
        return {
            method => 'cancel',
            stage  => 'commit',
            next   => 'illview',
            value  => $params,
        };
    } else {

        # Invalid stage, return error.
        return {
            error   => 1,
            status  => 'unknown_stage',
            message => '',
            method  => 'cancel',
            stage   => $params->{stage},
            value   => {},
        };
    }
}

=head3 status

  my $response = $backend->create({
    request => $requestdetails,
    other   => $other,
  });

We will try to retrieve the status of a specific request.

We will generally use $request.  This will be supplied at all times through
Illrequest.  $other may be supplied using templates.

=cut

sub status {

  # -> request the current status of a confirmed ILL order
  my ($self, $params) = @_;
  return {
    error   => 1,
    status  => 404,
    message => "Not Implemented",
    method  => 'status',
    stage   => 'fake',
    value   => {},
  };
}

=head3 availability_check_info

Utilized if the AutoILLBackend sys pref is enabled

=cut

sub availability_check_info {
    my ( $self, $params ) = @_;

    my $endpoint = '/api/v1/contrib/' . $self->name . '/ill_backend_availability_koha?metadata=';

    return {
        endpoint => $endpoint,
        name     => $self->name,
    };
}

#### Helpers

=head3 _search

  my $response = $self->_search($query, $other);

Given a search query hashref, perform a Z3950 search against the specified
targets and return the results (and add the results to the reserviour).

$other is a hashref of additional information which may be used by the
backend.

=cut

sub _search {
  my ($self, $search, $other) = @_;

  # Mock C4::Template object used for passing parameters
  # (Z3950Search compatabilty shim)
  my $mock = MockTemplate->new;
  Z3950Search($search, $mock);

  my $response = {
    numberpending   => $mock->param('numberpending'),
    current_page    => $mock->param('current_page'),
    total_pages     => $mock->param('total_pages'),
    show_nextbutton => $mock->param('show_nextbutton'),
    show_prevbutton => $mock->param('show_prevbutton'),
    results         => $mock->param('breeding_loop'),
    servers         => $mock->param('servers'),
    errors          => $mock->param('errconn')
  };

  my @rest_results = ();
  my $ua = LWP::UserAgent->new;
  foreach my $target_key ( keys %{ $self->{targets} } ) {

      my $target = $self->{targets}->{$target_key};
      next if ( !$target->{rest_api_endpoint} );
      my $search_params;
      if ( $search->{issn} ) {
          $search->{issn} =~ s/^\s+|\s+$//g;
          push( @{ $search_params->{'-or'} }, [ { 'issn' => $search->{issn} } ] );
      } elsif ( $search->{isbn} ) {
          $search->{isbn} =~ s/^\s+|\s+$//g;
          push( @{ $search_params->{'-or'} }, [ { 'isbn' => $search->{isbn} } ] );
      } else {
          if ( $search->{title} ) {
              push( @{ $search_params->{'-or'} }, [ { 'title' => { 'like' => '%' . $search->{title} . '%' } } ] );
          }
      }

      my $encoded_login = encode_base64( $target->{user} . ':' . $target->{password} );
      my @req_headers   = (
          'Accept'        => 'application/json',
          'Authorization' => "Basic $encoded_login"
      );

      # Only fetch 3 biblios, or the search will take too long and timeout
      # TODO: Make this configurable (?)
      my $search_response = $ua->request(
          GET $target->{rest_api_endpoint} . "/api/v1/biblios?q=" . encode_json($search_params).'&_per_page=3',
          @req_headers
      );

      if ( !$search_response->is_success ) {
          _warn_api_errors_for_warning(
              'Unable to fetch biblios information for target ' . $target_key,
              $search_response
          );
          return;
      }
      my $decoded_content = decode_json( $search_response->decoded_content );

      _add_libraries_info( $decoded_content, $target->{rest_api_endpoint}, $encoded_login );

      foreach my $result ( @{$decoded_content} ) {
        $result->{server} = $target_key;
        $result->{record_link} =
            $target->{rest_api_endpoint} . "/cgi-bin/koha/opac-detail.pl?biblionumber=" . $result->{biblio_id};
        $result->{remote_biblio_id} = $result->{biblio_id};
        $result->{doi} = $other->{doi};
        $result->{year} = $other->{year};
        $result->{article_title} = $other->{article_title};
        $result->{unauthenticated_first_name} = $other->{unauthenticated_first_name};
        $result->{unauthenticated_last_name} = $other->{unauthenticated_last_name};
        $result->{unauthenticated_email} = $other->{unauthenticated_email};

        push @{ $response->{results} }, $result;
      }
  }
  # Return search results
  return $response;
}

=head3 _add_libraries_info

_add_libraries_info( $decoded_content, $rest_libraries, $target->{rest_api_endpoint}, $encoded_login );

Prepares a response for the UI by fetching items information and
converting it into a human-readable format.

=cut

sub _add_libraries_info {
    my $response      = shift;
    my $base_url      = shift;
    my $encoded_login = shift;
    my $ua            = LWP::UserAgent->new;
    my $out           = [];

    foreach my $record ( @{$response} ) {

        my @items_req_headers = (
            'Accept'        => 'application/json',
            'Authorization' => "Basic $encoded_login",
            'x-koha-embed'  => '+strings'
        );

        my $items = $ua->request(
            GET sprintf(
                '%s/api/v1/biblios/%s/items?_per_page=-1',
                $base_url,
                $record->{biblio_id},
            ),
            @items_req_headers
        );

        my $items_response = decode_json( $items->decoded_content );
        if ( !$items->is_success ) {
            _warn_api_errors_for_warning(
                'Unable to fetch items information for biblio ' . $record->{biblio_id},
                $items_response
            );
            return;
        }

        my $final_items = [
            map {
                $_->{strings} = $_->{_strings};
                delete $_->{_strings};
                $_->{libraryname} = $_->{strings}->{home_library_id}->{str} // $_->{strings}->{holding_library_id}->{str};
                $_;
            } @{$items_response}
        ];

        my @sorted_items_response =
            sort { $a->{libraryname} cmp $b->{libraryname} } @{$final_items};

        $record->{api_items} = \@sorted_items_response;
    }
}

=head3 _warn_api_errors_for_warning

  my $error_messages = _get_api_errors_for_warning($errors);

This function takes an arrayref of error hashrefs and warns a formatted
string of error messages.

=cut

sub _warn_api_errors_for_warning {
    my $message = shift;
    my $response = shift;

    my $errors = $response->{errors} || [ $response->status_line ];

    my $items_error_message_str;
    foreach my $error ( @{$errors} ) {
      if (ref $error eq 'HASH') {
          foreach my $key ( keys %{$error} ) {
              $items_error_message_str .= "$key: $error->{$key}, ";
          }
          $items_error_message_str .= "\n";
      }else{
          $items_error_message_str .= "$error\n";
      }
    }
    warn 'Koha2Koha ILL backend: ' . $message . '. Error: ' . $items_error_message_str;
}

=head3 _fail

=cut

sub _fail {
  my @values = @_;
  foreach my $val (@values) {
    return 1 if (!$val or $val eq '');
  }
  return 0;
}

=head3 _request

  my $rsp = $self->_request($params);

Given a set of query details, perform an http request and return the response
or set an error flag.

=cut

sub _request {
  my ($self, $param) = @_;
  my $method     = $param->{method};
  my $url        = $param->{url};
  my $content    = $param->{content};
  my $additional = $param->{additional};
  my $headers    = $param->{headers};

  my $req = HTTP::Request->new($method => $url);

  # add content if specified
  if ($content) {
    $req->content($content);
    $req->header('Content-Type' => 'text/xml');
  }

  if ($headers) {
    foreach my $key ( keys %{$headers} ) {
      $req->header($key => $headers->{$key});
    }
  }

  my $ua  = LWP::UserAgent->new;
  my $res = $ua->request($req);
  if ($res->is_success) {
    return $res->content;
  }
  $self->{error} = {status => $res->status_line, content => $res->content};
  return;
}

=head3 _validate_borrower

Given a borrower cardnumber, identify the borrower and check their eligability
to submit requests. Return an arrayref of the borrower match count followed by
the first borrowers details.

=cut

sub _validate_borrower {

  # Perform cardnumber search.  If no results, perform surname search.
  # Return ( 0, undef ), ( 1, $brw ) or ( n, $brws )
  my ($input, $action) = @_;
  my $patrons = Koha::Patrons->new;
  my ($count, $brw);
  my $query = {cardnumber => $input};
  $query = {borrowernumber => $input} if ($action eq 'search_cont');

  my $brws = $patrons->search($query);
  $count = $brws->count;
  my @criteria = qw/ surname userid firstname end /;
  while ($count == 0) {
    my $criterium = shift @criteria;
    return (0, undef) if ("end" eq $criterium);
    $brws = $patrons->search({$criterium => $input});
    $count = $brws->count;
  }
  if ($count == 1) {
    $brw = $brws->next;
  }
  else {
    $brw = $brws;    # found multiple results
  }
  return ($count, $brw);
}

sub _return_template_error {
  my ( $message, $value ) = @_;

  return {
      error   => 1,
      status  => '',
      message => $message,
      method  => 'confirm',
      stage   => 'confirm',
      next    => '',
      value   => $value
  }
}

=head3 _get_request_details

Given a request, extracts the details from the request and the other patron's
data, and returns a hashref with the details.

=cut

sub _get_request_details {
  my ( $request, $remote_id ) = @_;

  return {
      target              => $request->{target},
      target_item_id      => $request->{target_item_id},
      target_library_id   => $request->{target_library_id},
      target_library_name => $request->{target_library_name},
      bib_id              => $remote_id,
      article_title       => $request->{article_title},
      title               => $request->{title},
      author              => $request->{author},
      isbn                => $request->{isbn},
      year                => $request->{year},
      issn                => $request->{issn},
      doi                 => $request->{doi},
  };
}

=head3 _add_from_breeding

  my $record = $self->_add_from_breeding($breedingid);

Given a MARCBreedingID, we should lookup the record from the reserviour, add it
to the catalogue as a temporary record and return the new records biblionumber
and the remote records biblionumber.

=cut

sub _add_from_breeding {
  my ($self, $breedingid, $framework) = @_;

  # Fetch record from reserviour
  my ($marc, $encoding) = GetImportRecordMarc($breedingid);
  my $record = MARC::Record->new_from_usmarc($marc);

  # Stash the remote biblionumber
  my $remote_id = $record->field('999')->subfield('c');

  # Remove the remote biblionumbers
  my @biblionumbers = $record->field('999');
  $record->delete_fields(@biblionumbers);

  # Remove the remote holdings
  my @holdings = $record->field('952');
  $record->delete_fields(@holdings);

  # Set the record to suppressed
  $self->_set_suppression($record);

  # Store the record
  my $biblionumber = AddBiblio($record, $framework);

  # Return the new records biblionumber and the remote records biblionumber
  return ($biblionumber, $remote_id);
}

=head3 _validate_form_params

    _validate_form_params( $other, $result, $params );

Validate form parameters and return the validation result

=cut

sub _validate_form_params {
    my ( $other, $result, $params ) = @_;

    my $failed = 0;
    if ( !$other->{'branchcode'} ) {
        $result->{status} = "missing_branch";
        $result->{value}  = $params;
        $failed           = 1;
    } elsif ( !Koha::Libraries->find( $other->{'branchcode'} ) ) {
        $result->{status} = "invalid_branch";
        $result->{value}  = $params;
        $failed           = 1;
    }

    return ( $failed, $result );
}

=head3 _set_suppression

  my $result = $self->_set_suppression($record);

Given a MARC::Record, set the suppression bit, return success.

=cut

sub _set_suppression {
  my ($self, $record) = @_;

  my $field942 = $record->field('942');

  # Set Supression (942)
  if (defined $field942) {
    $field942->update(n => '1');
  }
  else {
    my $new942 = MARC::Field->new('942', '', '', n => '1');
    $record->insert_fields_ordered($new942);
  }
  return 1;
}

=head1 AUTHORS

Alex Sassmannshausen <alex.sassmannshausen@ptfs-europe.com>
Martin Renvoize <martin.renvoize@ptfs-europe.com>

=cut

# Contained MockTemplate object is a compatability shim used so we can pass
# a minimal object to Z3950Search and thus use existing Koha breeding and
# configuration functionality.

{

  package MockTemplate;

  use base qw(Class::Accessor);
  __PACKAGE__->mk_accessors("vars");

  sub new {
    my $class = shift;
    my $self = {VARS => {}};
    bless $self, $class;
  }

  sub param {
    my $self = shift;

    # Getter
    if (scalar @_ == 1) {
      my $key = shift @_;
      return $self->{VARS}->{$key};
    }

    # Setter
    while (@_) {
      my $key = shift;
      my $val = shift;

      if    (ref($val) eq 'ARRAY' && !scalar @$val) { $val = undef; }
      elsif (ref($val) eq 'HASH'  && !scalar %$val) { $val = undef; }
      if    ($key) {
        $self->{VARS}->{$key} = $val;
      }
      else {
        warn "Problem = a value of $val has been passed to param without key";
      }
    }
  }
}

1;
