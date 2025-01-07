[% IF whole.value.results %]
<table>
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
          _ "&amp;remote_biblio_id=" _ result.remote_biblio_id
          _ "&amp;breedingid=" _ result.breedingid %]
          <td>
            [% IF result.api_items %]
              <table class="w-100">
                  [% FOREACH item IN result.api_items %]
                  <tr>
                    <td class="w-100">
                      <strong>[% item.libraryname | $raw %]</strong>
                      [% IF item.public_notes %]
                        ([% item.public_notes | $raw %])
                      [% END %]
                      [% IF item.itemnumber == whole.current_item %]
                        <span class="badge text-bg-warning">Current requested item</span>
                      [% END %]
                      [% IF whole.previous_requested_items.grep('^' _ item.itemnumber _ '$').size %]
                        <span class="badge text-bg-danger">Previously requested item</span>
                      [% END %]
                    </td>
                    <td>
                      [% IF item.itemnumber == whole.current_item || whole.previous_requested_items.grep('^' _ item.itemnumber _ '$').size%]
                        <a class="btn btn-sm btn-default disabled" href="[% target _ "&amp;remote_item_id=" _ item.itemnumber %]">Request this item</a>
                      [% ELSE %]
                        <a class="btn btn-sm btn-default" href="[% target _ "&amp;remote_item_id=" _ item.itemnumber %]">Request this item</a>
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