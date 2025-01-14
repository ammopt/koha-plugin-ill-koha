[% IF whole.stage == "confirm" && !whole.error %]
    <h2>Confirm request</h2>
    <p>Proceeding with this action will set this request to 'Requested' and send a request email to:</p>
    <p>
        <table border="1" cellpadding="5" cellspacing="0">
        <tr>
            <td>Target</td>
            <td>[% whole.value.target %]</td>
        </tr>
        <tr>
            <td>Library</td>
            <td>[% whole.value.target_library_name %]</td>
        </tr>
        <tr>
            <td>Email</td>
            <td>[% whole.value.target_library_email %]</td>
        </tr>
        </table>
    </p>
    [% base_url = "/cgi-bin/koha/ill/ill-requests.pl" %]
    [% proceed_url = base_url _ "?method=confirm&stage=confirm" _ "&illrequest_id=" _ request.illrequest_id %]
    <a class="btn btn-sm btn-primary" href="[% proceed_url | url %]">Confirm request</a>
    <a class="btn btn-sm btn-default cancel" href="[% base_url | url %]">Cancel</a>
    </p>
[% ELSE %]
    <p>We encountered an unexpected situation</p>
[% END %]
