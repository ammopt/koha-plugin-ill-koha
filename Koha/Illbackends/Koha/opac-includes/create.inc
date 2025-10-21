<!-- Error Handling -->
[% IF whole.error %]
    <!-- Dispatch on Status -->
    <p>We encountered an error:</p>
    <ol>
        <li>[% whole.status %]</li>
        <li>[% whole.message %]</li>
    </ol>
[% END %]

[% IF whole.stage == "search_form" %]
    <h2>Search a dummy request</h2>
    <form class="validated" method="post" action="/cgi-bin/koha/opac-illrequests.pl">
        [% INCLUDE 'csrf-token.inc' %]
        <input type="hidden" name="stage" value="[% whole.stage %]"/>
        <input type="hidden" name="method" value="[% whole.method %]"/>
        <input name="backend" id="method" value="[% whole.value.other.backend %]" type="hidden"/>
        <fieldset class="rows">
            <ol>
                <li>
                    <label class="required" for="search">Search string: </label>
                    <input class="required" required="required" type="text" name="search" value="" />
                    <span class="required">Required</span>
                </li>
                <li>
                    <label class="required" for="branchcode">Pickup branch: </label>
                    <select class="required" required="required" id="branchcode" name="branchcode">
                        [% FOREACH branch IN branches %]
                            <option value="[% branch.branchcode %]">
                        [% branch.branchname %]
                            </option>
                        [% END %]
                    </select>
                    <span class="required">Required</span>
                </li>
                <li>
                    <label class="required" for="medium">Request type: </label>
                    <select class="required" required="required" id="medium" name="medium">
                        [% FOREACH type IN types %]
                            <option value="[% type %]">[% type %]</option>
                        [% END %]
                    </select>
                    <span class="required">Required</span>
                </li>
            </ol>
        </fieldset>
        <fieldset class="action">
            <input type="submit" class="btn btn-primary" value="Search"/>
            <a class="cancel" href="/cgi-bin/koha/opac-illrequests.pl">Cancel</a>
        </fieldset>
    </form>

[% ELSIF whole.stage == "search_results" %]
    <h2>Select a request</h2>
    [% IF whole.value.results %]
        <table class="table table-bordered table-striped" id="koha-ill-plugin-search-results-table">
            <thead>
                <tr>
                    <th id="id">ID</th>
                    <th id="title">Title</th>
                    <th id="author">Author</th>
                    <th id="select">Select?</th>
                </tr>
            </thead>
            <tbody>
                [% FOREACH result IN whole.value.results %]
                    <tr>
                        <td>[% result.remote_biblio_id %]</td>
                        <td>[% result.title %]</td>
                        <td>[% result.author %]</td>
                        [% target = "/cgi-bin/koha/opac-illrequests.pl"
                        _ "?method=" _ whole.method
                        _ "&amp;stage=" _ whole.stage
                        _ "&amp;backend=" _ whole.backend
                        _ "&amp;branchcode=" _ whole.branchcode
                        _ "&amp;borrowernumber=" _ whole.borrowernumber
                        _ "&amp;target=" _ result.server
                        _ "&amp;illrequest_id=" _ whole.illrequest_id
                        _ "&amp;author=" _ result.author
                        _ "&amp;title=" _ result.title
                        _ "&amp;issn=" _ result.issn
                        _ "&amp;isbn=" _ result.isbn
                        _ "&amp;remote_biblio_id=" _ result.remote_biblio_id
                        _ "&amp;id=" _ result.id
                        _ result.URL_fields_to_append_string
                        %]
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
                                        <a class="btn btn-sm btn-default disabled">Request this item</a>
                                    [% ELSE %]
                                        <form action="/cgi-bin/koha/opac-illrequests.pl" method="POST">
                                            [% INCLUDE 'csrf-token.inc' %]
                                            <input type="hidden" name="method" value="[% whole.method | html %]"/>
                                            <input type="hidden" name="stage" value="[% whole.stage | html %]"/>
                                            <input type="hidden" name="backend" value="[% whole.backend | html %]"/>
                                            <input type="hidden" name="branchcode" value="[% whole.branchcode | html %]"/>
                                            <input type="hidden" name="borrowernumber" value="[% whole.borrowernumber | html %]"/>
                                            <input type="hidden" name="target" value="[% result.server | html %]"/>
                                            <input type="hidden" name="illrequest_id" value="[% whole.illrequest_id | html %]"/>
                                            <input type="hidden" name="author" value="[% result.author | html %]"/>
                                            <input type="hidden" name="title" value="[% result.title | html %]"/>
                                            <input type="hidden" name="issn" value="[% result.issn | html %]"/>
                                            <input type="hidden" name="isbn" value="[% result.isbn | html %]"/>
                                            <input type="hidden" name="remote_biblio_id" value="[% result.remote_biblio_id | html %]"/>
                                            <input type="hidden" name="id" value="[% result.id | html %]"/>
                                            <input type="hidden" name="target_item_id" value="[% itemnumber | html %]"/>
                                            <input type="hidden" name="target_library_id" value="[% item.home_library_id | html %]"/>
                                            <input type="hidden" name="target_library_name" value="[% item.libraryname | html %]"/>

                                            [% FOREACH f IN result.URL_fields_to_append_array %]
                                                [% IF f.value %]
                                                    <input type="hidden" name="[% f.name | html %]" value="[% f.value | html %]"/>
                                                [% END %]
                                            [% END %]

                                            <input type="submit" class="btn btn-sm btn-default" value="Request this item"/>
                                        </form>
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

[% ELSE %]
    <p>We encountered an unexpected situation</p>

[% END %]
