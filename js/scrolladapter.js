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
	
	Note: To fake the JSON result from something other than SimpleListView,
		you must include in the result the following fields:
			list_length
			list
			next_url
			prev_url
			total_rows
			actual_page_end
			
		Here's an actual example:
			actual_page_end: 125
			list: [{supplier_url:&nbsp;, show_price:1, unit_size_umid:Capsules, upc:&nbsp;, itemnum:AGZ090,…},…]
			list_length: 25
			next_url: "/office/inventory?start=125&length=25"
			prev_url: "/office/inventory?start=75&length=25"
			total_rows: "2424"
			
		Your controller must use the following query string fields:
			start
			length
			query
			output_fmt (will be set to 'json')
	
*/	

// AWSV = AppCore.Web.SimpleListView :-)
function AWSV_AjaxScrollAdapter(args) {

	if(!args.pageLength)
		args.pageLength = 25;
		
	if(!args.requestHook)
		args.requestHook = function(data){ 
			return data;
		};
	
	if(!args.responseHook)
		args.responseHook = function(data){ 
			return data;
		};
	
	
	var $rowTemplate = args.rowTemplate,
		   $list = args.list;
	
	if(!$rowTemplate)
		$rowTemplate = $('#listrow-tmpl');
	
	if(!$list)
		$list = $('#list_table tbody');
	
	
		
	var $loadingModal = $('<div class="modal" tabindex="-1" role="dialog" aria-hidden="true" style="margin-top:10%">'
		+ '<div class="modal-dialog modal-sm"><div class="modal-content">'
		+ '<div class="modal-body" style="text-align:center;padding:2em">'
		+ '<b><i class="fa fa-spin fa-spinner fa-lg"></i> Please wait, loading data ...</b>'
		+' </div></div></div></div>');
	
	//$div.modal('show');	
	//
	
	if(args.useLoadingModal)
		$loadingModal.appendTo(document.body);
	else
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
	
	var searchUpdate = function()
	{
		//console.log("scrolladapter.js: searchUpdate:", args.pageFilter);
		
		nextPageStartRow = 0;
		loadResultsPage(nextPageStartRow);
	}
	
	var bufferSearchUpdate = function() 
	{
		// Yes, using bufferNextPageLoad because ".locked" is already set throughout the code
		if(bufferNextPageLoad.locked)
			return;
		
		// Delay X ms then load the result from the server
		clearTimeout(bufferNextPageLoad.tid);
		bufferNextPageLoad.tid = setTimeout(searchUpdate, args.quietMillis || 100);
		
		//console.log("scrolladapter.js: bufferSearchUpdate:", args.pageFilter);
	}
	
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
		
		if(result.page_start == 0)
		{
			$list.empty();
			//$(window).scrollTop(0);
		}
		
		for(var i=0; i<result.list_length; i++)
		{
			var rowData = result.list[i],
			    tmplOut = $rowTemplate.tmpl(rowData);
			   
			//console.debug("AWSV_AjaxScrollAdapter: result:", result,", data row:",i,", rowData:",rowData,", tmplOut:",tmplOut,", adding to list:",$list);
			
			tmplOut.appendTo($list);
		}
		
		hasMoreResults = result.next_url != null;
		
		//console.debug("AWSV_AjaxScrollAdapter: hasMoreResults:", hasMoreResults, ", renderRequest: ",result);
		
		updatePagingDisplay(result);
		
		$('#list_table').trigger('scrolladapter.rendered');
		
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
		if(args.useLoadingModal)
			$loadingModal.modal('hide');
		else
		{
			$loadingSpinners.hide();
			$('.paging_link.next_link').show();
		}
	};
	
	var unloadingState = false;
	$(window).bind("beforeunload", function () {
		unloadingState = true;
	});
	
	var loadResultsPage = function(page) {
		
		bufferNextPageLoad.locked = true;
		
		//console.debug("loadResultsPage: data:",data, "page:",page);
		//alert("loadResultsPage: "+page);
		
		//specialRows.noResult.remove();
		
		//if(page == 0)
			//$list.prepend(specialRows.loading);
		//else
			//$list.append(specialRows.loading);
		
		if(args.useLoadingModal)
			$loadingModal.modal('show');
		else
		{
			$loadingSpinners.show();
			$('.paging_link.next_link').hide();
		}
		
		//console.log("scrolladapter.js: loadResultsPage:", args.pageFilter,", page:",page);
		
		var requestData = {
			page:		page,
			results:	null,
			rxd:		false,
			id:		requestCounter ++,
		};
		
		requestQueue.push(requestData);
		
		//console.debug("AWSV_AjaxScrollAdapter: loadResultsPage: ",page,", url:",(args.pageUrl || '.'));
		
		
		$.ajax({
			url:  args.pageUrl || '.',
			data: args.requestHook({
				start:	page,
				length: args.pageLength,
				query:  args.pageFilter,
				output_fmt: 'json',
			}),
			success: function(result) {
				//console.debug("ajax results:",result);
				
				//console.log("scrolladapter.js: loadResultsPage:", args.pageFilter,", page:",page,", results:",result);
				
				bufferNextPageLoad.locked = false;
				
				requestData.results = args.responseHook(result);
				requestData.rxd     = true;
				
				processResultQueue();
			},

			error: function(result) {
				//specialRows.loading.remove();
				
				bufferNextPageLoad.locked = false;
				
				// 'unloadingState' suggested by http://stackoverflow.com/questions/15326627/jquery-ajax-error-when-leaving-page
				if(!unloadingState)
				{
					//alert("Error:");
					//console.debug(result.responseText);
					$(document.body).html('<div class="alert alert-danger style="margin:1em 4em">'+result.responseText+'</div>');
				}
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
	
	if(!args.disableAutoLoadNextPage)
		bufferNextPageLoad();
	
	
	// If args.search provided, enable auto-search
	if(args.search && args.search[0])
	{
		// jQuery plugin: PutCursorAtEnd 1.0
		// http://plugins.jquery.com/project/PutCursorAtEnd
		// by teedyay
		//
		// Puts the cursor at the end of a textbox/ textarea

		// codesnippet: 691e18b1-f4f9-41b4-8fe8-bc8ee51b48d4
		(function($)
		{
			jQuery.fn.putCursorAtEnd = function()
			{
				return this.each(function()
				{
					$(this).focus()

					// If this function exists...
					if (this.setSelectionRange)
					{
						// ... then use it
						// (Doesn't work in IE)

						// Double the length because Opera is inconsistent about whether a carriage return is one character or two. Sigh.
						var len = $(this).val().length * 2;
						this.setSelectionRange(len, len);
					}
					else
					{
						// ... otherwise replace the contents with itself
						// (Doesn't work in Google Chrome)
						$(this).val($(this).val());
					}

					// Scroll to the bottom, in case we're in a tall textarea
					// (Necessary for Firefox and Google Chrome)
					this.scrollTop = 999999;
				});
			};
		})(jQuery);
		
		args.search
			.putCursorAtEnd()
			.attr('autocomplete', 'off')
			.on('keyup', function() {
				var  $this = $(this),
				val = $this.val();
				
				args.pageFilter = val;
				
				//console.log("scrolladapter.js: new args.pageFilter:", args.pageFilter);
				
				bufferSearchUpdate();
			});
	}
}
