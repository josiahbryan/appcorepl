/* Include this file in a template used by AppCore::Web::SimpleListView
	and activate it like so:

	AWSV_AjaxScrollAdapter({
			pageUrl:	'%%page_path%%',	// URL of the controller that uses AppCore::Web::SimpleListView
			pageFilter:	'%%query%%',		// The current filter / search query
			pageStart:	%%page_start%% + %%page_length%%, // The row number of the current page ENDS on
			pageLength:	25, //%%page_length%%,	// Your choice - either set the number of rows to load via AJAX or use the current length of the page
			rowTemplate:	$('#listrow-tmpl'),	// The template to use for the rows (same ID as given to tmpl2jq, shown below)
			list: 		$('#list_table tbody'),	// The TBODY of the list to which to append newly loaded rows
			quietMillis:	100,			// The number of milliseconds to wait for the user to stop scrolling to prevent overwhelming the server
		});
	
	Note: Be sure to add this to the same template: 
		<script src='/appcore/js/jquery.tmpl.js'></script>
		
	To make it work, you must wrap the <tr></tr> of the main list in:

	<!--tmpl2jq:listrow-tmpl-->
		<tr>
		...
		</tr>
	<!--/tmpl2jq-->

	And make sure $ENABLE_TMPL2JQ_BLOCK_CLONE is set to '1' in your appcore.conf.pl
	
	The only change to the server-side code that uses SimpleListview is to change your line that looks like:
		
		my $html = $view->output();
		
	To something like:
	
		# Apply the desired format
		$view->set_output_format(
			$req->output_fmt eq 'json' ? 'json' :
			$req->output_fmt eq 'xls'  ? 'xls'  :
			                             'html');
		
		# Returns the list in the requested format (currently, only XLS, JSON, and HTML are supported)
		my $data = $view->output;
		
		# Return XLS or JSON if requested
		return $class->output_json($data)
			if $req->output_fmt eq 'json';
			   
		return $class->output_data($view->content_type, $data)
			if $req->output_fmt eq 'xls';
		
	And later on when you do $r->output($html) or $class->respond($html), just do $class->respond($data) or $r->output($data) instead.
	(This is assuming $class is an instance of AppCore::Web::Controller.)
			
	Note that this file expects 'output_fmt' to set the output to JSON - so make sure you use the 'output_fmt' request field as shown above.
	
	Note: The loading spinner depends on font-awesome being used in the page.
*/	
		

// AWSV = AppCore.Web.SimpleListView :-)
function AWSV_AjaxScrollAdapter(args) {

	if(!args.pageLength)
		args.pageLength = 25;
	
	var $rowTemplate = args.rowTemplate,
		   $list = args.List;
	
	if(!$rowTemplate)
		$rowTemplate = $('#listrow-tmpl');
	
	if(!$list)
		$list = $('#list_table tbody');
	
	$('.paging_link.next_link').each(function() {
		var $spin = $('<i class="fa paging-spinner fa-spin fa-spinner" style="display:inline-block;margin:0 1rem;margin-right:-24px"></i>');
		$spin.insertAfter($(this));
	});
	
	var $loadingSpinners = $('.paging-spinner');
	$loadingSpinners.hide();
	
	var nextPageStartRow = args.pageStart;
	var hasMoreResults = true;
	
	// We're using a request queue so that servers that respond
	// with requests out-of-order can be properly sequenced
	var requestQueue = [];
	var requestCounter = 0;
	
	var updatePagingDisplay = function(result) {
	
		var $pg = $('.paging_display');
		var $nu = $('.paging_link.next_link');
		var $pu = $('.paging_link.prev_link');
		
		if(result.next_url == null)
			$nu.hide();
		else
			$nu.attr('href', result.next_url);
			
		if(result.prev_url == null)
			$pu.hide();
		//else
		//	$pu.attr('href', result.prev_url);
		
		if(result.next_url == null &&
			args.pageStart <= 1)
		{
			$pg.html('Showing <b>'+result.total_rows+'</b> items');
		}
		else
		{
			//$pg.html('Showing <b>'+(args.pageStart == 0 ? 1 : args.pageStart)+'</b> - <b>'+result.actual_page_end+'</b> of <b>'+result.total_rows+'</b> items');
			$pg.html('Showing <b>'+result.actual_page_end+'</b> of <b>'+result.total_rows+'</b> items');
		}
			
	}
	
	var renderRequest = function(result) {
	
		for(var i=0; i<result.list_length; i++)
		{
			var rowData = result.list[i];
			$rowTemplate
				.tmpl(rowData)
				.appendTo($list);
		}
		
		hasMoreResults = result.next_url != null;
		
		//console.debug("AWSV_AjaxScrollAdapter: hasMoreResults:", hasMoreResults, ", renderRequest: ",result);
		
		updatePagingDisplay(result);
		
	}
	
	var processResultQueue = function() {
		
		// Sort requests by sequence they were inserted
		requestQueue.sort(function(a,b) {
			return (a.id - b.id);
		});
		
		// Verify all results are complete - if anything is
		// incomplete (such as result 2 out of 5),
		// we want to wait until all data is completed
		var allCompleted = true;
		for(var x=0; x<requestQueue.length; x++)
			if(!requestQueue[x].rxd)
				allCompleted = false;
				
		//console.debug("processResultQueue: allCompleted:",allCompleted, ", queue:",requestQueue);
		
		if(!allCompleted)
			return;
		
		// Process the result queue since all are completed
		for(var x=0; x<requestQueue.length; x++)
		{
			//console.debug("processResultQueue: processing #",x);
			var requestData = requestQueue[x];
		
			renderRequest(requestData.results);
		}
		
		// Suggested as fastest method to empty an array 
		// from http://stackoverflow.com/questions/1232040/empty-an-array-in-javascript
		while(requestQueue.length > 0)
			requestQueue.pop();
		
		//specialRows.loading.remove();
		$loadingSpinners.hide();
	};
	
	var loadResultsPage = function(page) {
		
		//console.debug("loadResultsPage: data:",data, "page:",page);
		
		//specialRows.noResult.remove();
		
		//if(page == 0)
			//$list.prepend(specialRows.loading);
		//else
			//$list.append(specialRows.loading);
		
		$loadingSpinners.show();
		
		var requestData = {
			page:		page,
			filter:		args.pageFilter,
			results:	null,
			rxd:		false,
			id:		requestCounter ++,
		};
		
		requestQueue.push(requestData);
		
		//console.debug("AWSV_AjaxScrollAdapter: loadResultsPage: ",page,", url:",(args.pageUrl || '.'));
		
		$.ajax({
			url: args.pageUrl || '.',
			data: {
				start:	page,
				length: args.pageLength,
				output_fmt: 'json',
				query: args.pageFilter,
			},
			success: function(result) {
				//console.debug("ajax results:",result);
				
				bufferNextPageLoad.locked = false;
				
				requestData.results = result;
				requestData.rxd     = true;
				
				processResultQueue();
			},

			error: function(result) {
				//specialRows.loading.remove();
				
				bufferNextPageLoad.locked = false;
				
				//alert("Error:");
				//console.debug(result.responseText);
				$(document.body).html('<div class="alert alert-danger style="margin:1em 4em">'+result.responseText+'</div>');
			}
			
		});
	};
	
	var checkScrollPosition = function() {
		
		// Thanks to http://stackoverflow.com/questions/8794338/get-the-height-and-width-of-the-browser-viewport-without-scrollbars-using-jquery
		var viewportHeight;
		var viewportWidth;
		if (document.compatMode === 'BackCompat') {
			viewportHeight = document.body.clientHeight;
			viewportWidth = document.body.clientWidth;
		} else {
			viewportHeight = document.documentElement.clientHeight;
			viewportWidth = document.documentElement.clientWidth;
		}
		
		
		var top = $(window).scrollTop();
		var height = viewportHeight;
		
		var scrollBottom = top + height;
		var contentHeight = $list.height();
		var triggerPercent = 90;
		var triggerPixel = contentHeight * (triggerPercent / 100);
		var hitTrigger = scrollBottom > triggerPixel;
		
		//console.debug(top,height,scrollBottom,contentHeight,triggerPixel,hitTrigger);
		
		if(hitTrigger)
			bufferNextPageLoad();
	};
	
	
	var nextPageLoad = function() {
		if(!hasMoreResults)
			return;
		
		loadResultsPage(nextPageStartRow);
		
		nextPageStartRow += args.pageLength;
	};
	
	var bufferNextPageLoad = function() {
		if(bufferNextPageLoad.locked)
			return;
		
		// Delay X ms then load the result from the server
		clearTimeout(bufferNextPageLoad.tid);
		bufferNextPageLoad.tid = setTimeout(nextPageLoad, args.quietMillis || 100);
	}
	
	$(window).on('scroll', checkScrollPosition);
	
	checkScrollPosition();
	
	//console.debug("AWSV_AjaxScrollAdapter: Online with args:" ,args);
	
	//bufferNextPageLoad();
}
