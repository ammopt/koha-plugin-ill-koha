[% IF whole.value.results %]
<fieldset class="rows">
  <button type="button" class="btn btn-link" onclick="history.back()">
      <i class="fa fa-arrow-left"></i> Go back
  </button>
[% IF whole.params.other %]
<button type="button" class="btn btn-link" onclick="toggleRequestDetails()">
  <i class="fa fa-caret-down" id="toggle-arrow"></i> <span id="toggle-button">Show request details</span>
</button>
<div id="request-details" style="display: none;">
  <ul class="list-unstyled">
    <table class="table table-sm table-striped">
      <thead>
        <tr>
          <th>Field</th>
          <th>Value</th>
        </tr>
      </thead>
      <tbody>
        [% FOREACH key IN whole.params.other.keys.sort %]
        [% IF key != 'csrf_token' && key != 'op' && key != 'stage' %]
        <tr>
          <td>[% key | replace("_", " ") | ucfirst | html %]</td>
          <td>[% whole.params.other.$key | html %]</td>
        </tr>
        [% END %]
        [% END %]
      </tbody>
    </table>
  </ul>
</div>
<script>
  function toggleRequestDetails() {
    var details = document.getElementById('request-details');
    var toggleButton = document.getElementById('toggle-button');
    var toggleArrow = document.getElementById('toggle-arrow');
    if (details.style.display === 'none') {
      details.style.display = 'block';
      toggleButton.textContent = 'Hide request details';
      toggleArrow.className = 'fa fa-caret-up';
    } else {
      details.style.display = 'none';
      toggleButton.textContent = 'Show request details';
      toggleArrow.className = 'fa fa-caret-down';
    }
  }
</script>
[% END %]
</fieldset>
<table id="results_table">
      <thead>
        <tr>
          <th id="partner">Partner</th>
          <th id="title">Title</th>
          <th id="author">Author</th>
          <th id="isbn">ISBN</th>
          <th id="issn">ISSN</th>
          <th id="select">Select?</th>
        </tr>
      </thead>
      <tbody>
        [% FOREACH result IN whole.value.results %]
        <tr>
          <td>[% result.server %]</td>
          <td>
            [% IF result.record_link %]
              <a target="_blank" href="[% result.record_link | url %]"><i class="fa fa-fw fa-external-link-square"></i>[% result.title %]</a>
            [% ELSE %]
              [% result.title %]
            [% END %]
          </td>
          <td>[% result.author %]</td>
          <td>[% result.isbn %]</td>
          <td>[% result.issn %]</td>
          [% target = "/cgi-bin/koha/ill/ill-requests.pl"
          _ "?method=" _ whole.method
          _ "&amp;target=" _ result.server
          _ "&amp;stage=" _ whole.stage
          _ "&amp;step=" _ whole.step
          _ "&amp;backend=" _ whole.backend
          _ "&amp;borrowernumber=" _ whole.borrowernumber
          _ "&amp;branchcode=" _ whole.branchcode
          _ "&amp;illrequest_id=" _ whole.illrequest_id
          _ "&amp;author=" _ result.author
          _ "&amp;title=" _ result.title
          _ "&amp;issn=" _ result.issn
          _ "&amp;isbn=" _ result.isbn
          _ "&amp;doi=" _ result.doi
          _ "&amp;year=" _ result.year
          _ "&amp;article_title=" _ result.article_title
          _ "&amp;remote_biblio_id=" _ result.remote_biblio_id
          _ "&amp;breedingid=" _ result.breedingid %]
          <td>
            [% IF result.api_items %]
              <table class="w-100">
                  [% FOREACH item IN result.api_items %]
                  [% SET itemnumber = item.item_id %]
                  <tr>
                    <td class="w-100">
                      <strong>[% item.libraryname | $raw %]</strong>
                      [% IF item.public_notes %]
                        ([% item.public_notes | $raw %])
                      [% END %]
                      [% IF itemnumber == whole.current_item && !whole.previous_requested_items.grep('^' _ itemnumber _ '$').size%]
                        <span class="badge text-bg-warning">Current item to be requested</span>
                      [% END %]
                      [% IF whole.previous_requested_items.grep('^' _ itemnumber _ '$').size %]
                        <span class="badge text-bg-danger">Previously requested item</span>
                      [% END %]
                    </td>
                    <td>
                      [% IF itemnumber == whole.current_item || whole.previous_requested_items.grep('^' _ itemnumber _ '$').size%]
                        <a class="btn btn-sm btn-default disabled" href="[% target _ "&amp;target_item_id=" _ itemnumber _ "&amp;target_library_id=" _ item.home_library_id _ "&amp;target_library_name=" _ item.libraryname %]">Request this item</a>
                      [% ELSE %]
                        <a class="btn btn-sm btn-default" href="[% target _ "&amp;target_item_id=" _ itemnumber _ "&amp;target_library_id=" _ item.home_library_id _ "&amp;target_library_name=" _ item.libraryname %]">Request this item</a>
                      [% END %]
                    </td>
                  </tr>
                  [% END %]
                </tbody>
              </table>
              [% result.libraries_content | $raw %]
            [% ELSE %]
                <a class="btn btn-sm btn-default" href="[% target %]">Request this item</a>
            [% END %]
            </td>
        </tr>
    [% END %]
</tbody>
</table>
[% ELSE %]
<p>We have no results</p>
[% END %]