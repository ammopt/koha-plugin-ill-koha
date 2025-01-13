[% IF whole.error %]
    <!-- Dispatch on Status -->
    <p>We encountered an error:</p>
    <ol>
        [% IF (whole.status) %]
            <li>[% whole.status %]</li>
        [% END %]
        <li>[% whole.message %]</li>
    </ol>
[% END %]

[% IF whole.stage == "confirm" %]
    <h2>Confirm request</h2>
    <p>Proceeding with this action will set this request to 'Requested'.</p>
    <p>This means that actions have been taken to request this request from a source.</p>
    <p>If you can confirm this has been done, please proceed.</p>
    <p>
    [% base_url = "/cgi-bin/koha/ill/ill-requests.pl" %]
    [% proceed_url = base_url _ "?method=confirm&stage=confirm" _ "&illrequest_id=" _ request.illrequest_id %]
    <a class="btn btn-sm btn-primary" href="[% proceed_url | url %]">Confirm request</a>
    <a class="btn btn-sm btn-default cancel" href="[% base_url | url %]">Cancel</a>
    </p>
[% ELSE %]
    <p>We encountered an unexpected situation</p>
[% END %]
