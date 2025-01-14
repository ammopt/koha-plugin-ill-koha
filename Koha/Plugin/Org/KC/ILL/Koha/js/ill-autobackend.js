$(document).ready(function() {
    let table_selector = '#koha-ill-plugin-search-results-table';
    let link = $( table_selector + ' a')[0];
    if ( link ) {
        console.log(link);
        var url = new URL(link.href);
        var target = url.searchParams.get("target");
        $("#koha-ill-plugin-search-results-table a")[0].click();
        $(table_selector).html(
            '<span id="verifying-availabilty" class="text-info"><i id="issues-table-load-delay-spinner" class="fa fa-spinner fa-pulse fa-fw"></i> ' +
                `Placing your request with ${target}...` +
                "</span>"
        );
    }
});
