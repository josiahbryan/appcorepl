
$(function() {
	
	if(window.FORM_DB_AJAX_LOADED)
		return;
	
	window.FORM_DB_AJAX_LOADED = true;
	
	function include(url, type, callback) {
		
		if(type == 'css')
		{
			var inc = document.createElement('link');
			
			inc.rel  = 'stylesheet';
			inc.href = url;
		
			var s = document.getElementsByTagName('script')[0];
			s.parentNode.insertBefore(inc, s);
		}
		else
		if(type == 'html')
		{
			$.ajax({
				url: url,
				type: 'GET',
				success: function(data) {
					
					var $data = $(data);
					
					$(document.body).append($data);
					
					if(typeof(callback) == 'function')
						callback($data);
				}
				
			});
		}
		
	}

	include('/appcore/js/form-db-ajax.inc.html', 'html', dbSearchDialogSetup);
	include('/appcore/css/form-db-ajax.css?_=1',     'css');

	/* Add in our search dialog */
	var pageSize = 25;
	var PAGE_ONE_BASED = false;
	var dbLookupOptions = {
		minimumInputLength: 0,
		//width: 600,
		ajax: {
			quietMillis: 250,
			dataType: 'json',
			data: function (term, page) { // page is the one-based page number tracked by Select2
				return {
					term:  term, //search term
					start: (PAGE_ONE_BASED ? (page - 1) : page) * pageSize, // page number
					limit: pageSize,
				};
			},
			results: function (data, page) {
				var more = (page * pageSize) < data.total; // whether or not there are more results available
				//console.debug("results parser: more:",more,", total:",data.total,", page:",page,", pageSize:",pageSize,", math:", (page*pageSize));
			
				// notice we return the value of more so Select2 knows if more results can be loaded
				return { results: data.list, more: more };
			},
			cacheKey: function( term, page/*, [... ]*/ ) {
				var x = [];
				for(var i=0; i<arguments.length; i++)
					x.push(arguments[i]);
				return x.join('.');
			},
		},
  
		// Override options, key is hookUrlRoot
		optionsOverride: {},
		
		// used by primeDbCache to prevent priming multiple times
		cacheStarted: {},
  
		cachedResults: {},
		
		resultCache: function(cacheKey, result) {
			
			var cache = this.cachedResults;// || this.cachedResults = {});
			
			if(result)
			{
				//console.log("resultCache: key:",cacheKey,": storing result:",result);
				cache[cacheKey] = result;
			}
			else
			{
				result = cache[cacheKey];
				//console.log("resultCache: key:",cacheKey,": returning result:",result);
			}
			
			return result;
		},
		
		formatResult: function(result) {
			if(this.optionsOverride[showItemChooser.hookUrlRoot] &&
			   this.optionsOverride[showItemChooser.hookUrlRoot].formatResult)
				return this.optionsOverride[showItemChooser.hookUrlRoot].formatResult(result);
			
			if(result == undefined || result == null || !result)
				return "";
				
			var text = result.value;
			//text = text.replace(/\s\((\d+[^\)]*)\)/, ' <span class=size>($1)</span>');
			return text;
		},
		formatSelection: function(result) {
			//console.log("formatSelection: result:",result,", current root:",showItemChooser.hookUrlRoot);
			
			if(this.optionsOverride[showItemChooser.hookUrlRoot] &&
			   this.optionsOverride[showItemChooser.hookUrlRoot].formatSelection)
				return this.optionsOverride[showItemChooser.hookUrlRoot].formatSelection(result);
			
			if(result == undefined || result == null || !result)
				return "";
				
			var text = result.value;
			//text = text.replace(/\s\((\d+[^\)]*)\)/, ' <span class=size>($1)</span>');
			return text;
		},
		initSelection: function(element, callback) {
			// the input tag has a value attribute preloaded that points to a preselected supplement's id
			// this function resolves that id attribute to an object that select2 can render
			// using its formatResult renderer - that way the supplement name is shown preselected
			var $elm = $(element),
				id = $elm.val(),
				initString = $elm.attr('x:initial-string');
			
			if(initString && initString != undefined)
			{
				callback({value: initString});
				return;
			}
			
			
			var id = $elm.val(),
				url = showItemChooser.hookUrlRoot+'/stringify?value=' + id;
				
			if (id !== "")
			{
				//console.log("initSelection: stringify: ",id);
				$.ajax(url)
					.done(function(data) {
						
						//console.debug("Got data from server:", data.result);
						callback({value: data.result.text});
					});
			}
		},
		
		//dropdownCssClass: "bigdrop", // apply css that makes the dropdown taller
		
		escapeMarkup: function (m) { return m; } // we do not want to escape markup since we are displaying html in results
	};
	
	window.dbLookupOptionsDebug = dbLookupOptions;
	
	function primeDbCache(urlRoot)
	{
		showItemChooser.hookUrlRoot = urlRoot;
		//loadResultsPage('', 0, true);
		
		var filter = '';
		var page = 0;
		
		var data = dbLookupOptions.ajax.data(filter, page);
		
		//console.debug("primeDbCache: url:",urlRoot,", data:",data, "page:",page);
		
		var cacheKey = dbLookupOptions.ajax.cacheKey(filter, page, showItemChooser.hookUrlRoot);
		
		var cacheData = dbLookupOptions.resultCache(cacheKey);
		if(cacheData)
			return;
		
		// This prevents priming the same URL multiple times
		if(dbLookupOptions.cacheStarted[cacheKey])
			return;
	
		dbLookupOptions.cacheStarted[cacheKey] = true;
		
		//console.log("primeDbCache: ",showItemChooser.hookUrlRoot+'/search',": ",data);
		$.ajax({
			url: showItemChooser.hookUrlRoot+'/search',
			data: data,
			success: function(result) {
				
				//console.debug("primeDbCache: url:",urlRoot,", loaded:",result);
				
				dbLookupOptions.resultCache(cacheKey, result);
			},

			error: function(result) {
				console.log(result.responseText);
// 				$(document.body).html('<div class="alert alert-danger style="margin:1em 4em">'+result.responseText+'</div>');
			}
			
		});
	}

	function dbSearchDialogSetup()
	{
		if(dbSearchDialogSetup.setupComplete)
			return;
	
		dbSearchDialogSetup.setupComplete = true;
		
		var $dialog   = $('.db-search-modal');
		
		// Move dialog out of current document flow position and to end of body to avoid any local-specific styles
		if(!$dialog.parent().is('body'))
		{
			$dialog.remove();
			$('body').append($dialog);
		}
		
		var $filter   = $dialog.find('.filter-control');
		var $list     = $dialog.find('.list-group');
		var $listWrap = $dialog.find('.list-group-wrapper');
		var $title    = $dialog.find('.db-search-title');
		
		var specialRows = {
			noResult: $('<a href="#" class="list-group-item special-row alert alert-danger">No items found</a>'),
			loading:  $('<a href="#" class="list-group-item special-row alert alert-warning"><i class="fa fa-spin fa-spinner"></i> Loading more results ...</a>')
		};
		
		var currentPage = 0;
		var currentFilter = '';
		var hasMoreResults = true;
		
		// We're using a request queue so that servers that respond
		// with requests out-of-order can be properly sequenced
		var requestQueue = [];
		var requestCounter = 0;
		
		var resultSetBuffer = [];
		var latestResultSetFilter = '';
		
		var resultSetCounter = 0;
		var clickFirstResultWhenLoaded = false;
		
		var updateList = function(processedResults) {
		
			var list       = processedResults.results;
			hasMoreResults = processedResults.more;
			
			//console.log("updateList: currentPage:",currentPage);
			
			if(currentPage == 0)
			{
				$list.empty();
				
				//return;
				
				$list.find('.list-group-item').removeClass('active');
			
				if(!list || list.length <= 0)
				{
					$list.append(specialRows.noResult);
					return;
				}
				
				// Add a special item at the very start of the list
				// to "clear" the current item (an option that, when clicked,
				// just clears the value in the box)
				if(!list[0].clearResultItem)
					list.unshift({
						clearResultItem: true
					});
				
			}
			
			//console.debug("updateList: currentPage:",currentPage,", items:", $list.find('.list-group-item'));
			
			latestResultSetFilter = currentFilter;
			
			var startIdx = resultSetBuffer.length;
			
			var currentText = 
				showItemChooser.currentWidget ?
				showItemChooser.currentWidget.find('.txt').text()
				: null;
			
			var currentId = 
				showItemChooser.currentElm ? 
				showItemChooser.currentElm.val() :
				null;
				
			var specialResetText = "<i>(Reset/Clear currently selected " + 
						($title.attr('placeholder') ?
							$title.attr('placeholder') : "Item")
						+ ")</i>";
			
			for(var i=0; i<list.length; i++)
			{
				var row = list[i];
				var html =
					row.clearResultItem ?
					specialResetText :
					dbLookupOptions.formatResult(row);
					
				//var isActive = !row.clearResultItem
				//	&& showItemChooser.currentWidget
				//	&& currentText == html;
				var isActive = row.clearResultItem ? false : 
					 row.id == currentId ? true: false;
					
				//console.debug("idx ",i,", this html:",html,", button html:",currentText,", isActive:",isActive);
				
				var $wrap = $('<a href="#" class="list-group-item"></a>')
					.html(html)
					.attr('x:id',  row.clearResultItem ? '0' : row.id)
					.attr('x:idx', i + startIdx)
					.addClass(row.clearResultItem ? 'clear-item' : (isActive ? 'active' : ''))
					.on('click', function() {
						
						var $elm       = $(this),
							id     = $elm.attr('x:id'),
							idx    = $elm.attr('x:idx'),
							result = resultSetBuffer[idx];
						
						var string = 
							result.clearResultItem ? '<i class="placeholder">(' + ($title.attr('placeholder') || 'Select an Item') + ')</i>' :
							dbLookupOptions.formatSelection(result);
						
						$('.db-search-modal').modal('hide');
						
						if(showItemChooser.currentWidget)
						{
							var w = showItemChooser.currentWidget;
							
							var title = string.replace(/<[^\>]+>/g,'');
							
							w.find('.txt').html(string);
							w.find('.btn').attr('title', title);
							
							showItemChooser.currentElm
								.val(id)
								.attr('title', title)
								.trigger('change');
							
							w.find('.btn').focus();
							
							//console.debug("Clicked row ",idx,", id:",id,", result:",result,", string:",string);
						}
						
						
						return false;
					});
					
					
				$list.append($wrap);
				
				if(isActive)
					$wrap.get(0).scrollIntoView();
				
				resultSetBuffer.push(row);
			}
			
			//console.debug("cur val:",curVal);
			
			if(clickFirstResultWhenLoaded)
			{
				clickFirstResultWhenLoaded = false;
				$list.find('.list-group-item:not(.clear-item)')
					.removeClass('active')
					.first()
					.addClass('active')
					.click();
			}
			else
			if(showItemChooser.currentElm)
			{
				var curVal = showItemChooser.currentElm.val();
				if(!curVal || curVal == 0 || latestResultSetFilter != '')
				{
					$list.find('.list-group-item:not(.clear-item)')
						.removeClass('active')
						.first()
						.addClass('active');
				}
			}
		};
		
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
			
				if(requestData.cacheOnly)
					continue;
					
				if(requestData.page == 0)
				{
					$list.empty();
					$listWrap.scrollTop(0);
				}
				
				var processed = dbLookupOptions.ajax.results(
					requestData.results,
					requestData.page);
				
				updateList(processed);
			}
			
			// Suggested as fastest method to empty an array 
			// from http://stackoverflow.com/questions/1232040/empty-an-array-in-javascript
			while(requestQueue.length > 0)
				requestQueue.pop();
			
			specialRows.loading.remove();
			$filter.removeClass('loading');
		};
		
		var loadResultsPage = function(filter, page, cacheOnly) {
		
			var data = dbLookupOptions.ajax.data(filter, page);
			
			//console.debug("loadResultsPage: filter:",filter,", data:",data, ", page:",page);
			
			specialRows.noResult.remove();
			
			//if(page == 0)
				//$list.prepend(specialRows.loading);
			//else
				$list.append(specialRows.loading);
			
			$filter.addClass('loading');
			
			resultSetCounter ++;
			
			var cacheKey = dbLookupOptions.ajax.cacheKey(filter, page, showItemChooser.hookUrlRoot);
			
			var requestData = {
				page:		page,
				filter:		filter,
				results:	null,
				rxd:		false,
				id:		requestCounter ++,
				cacheOnly:	cacheOnly,
				cacheKey:	cacheKey
			};
			
			requestQueue.push(requestData);
			
			var cacheData = dbLookupOptions.resultCache(cacheKey);
			if(cacheData)
			{
				bufferNextPageLoad.locked = false;
					
				requestData.results = cacheData;
				requestData.rxd     = true;
				
				processResultQueue();
				
				return;
			}
			
			
			$.ajax({
				url: showItemChooser.hookUrlRoot+'/search',
				data: data,
				success: function(result) {
					//console.debug("loadResultsPage: ajax results:",result);
					//console.debug("loadResultsPage: results from server:", result);
			
					bufferNextPageLoad.locked = false;
					
					requestData.results = result;
					requestData.rxd     = true;
					
					dbLookupOptions.resultCache(requestData.cacheKey, result);
					
					processResultQueue();
				},
	
				error: function(result) {
					specialRows.loading.remove();
					$filter.removeClass('loading');
					
					bufferNextPageLoad.locked = false;
					
					//alert("Error:");
					console.debug(result.responseText);
// 					$(document.body).html('<div class="alert alert-danger style="margin:1em 4em">'+result.responseText+'</div>');
				}
				
			});
		};
		
		
		var checkScrollPosition = function() {
			var top = $listWrap.scrollTop();
			var height = $listWrap.height();
			var scrollBottom = top + height;
			var contentHeight = $list.height();
			var triggerPercent = 90;
			var triggerPixel = contentHeight * (triggerPercent / 100);
			var hitTrigger = scrollBottom > triggerPixel;
			
			if(hitTrigger)
				bufferNextPageLoad();
		};
		
		var queryResults = function() {
			
			var filter = $filter.val();
			filter = filter.replace(/(^\s+|\s+$)/g, '');
			
			//filter = "zym";
			
			specialRows.noResult.remove();
			
			currentFilter   = filter;
			currentPage     = 0;
			hasMoreResults  = true;
			resultSetBuffer = [];
			
			//console.log("queryResults: currentFilter:",currentFilter,", currentPage:",currentPage,", filter=",$filter[0]);
			
			loadResultsPage(currentFilter, currentPage);
			
		};
		
		var bufferQueryResults = function(e) {
			if(!e)
				e = window.event;
			
			clickFirstResultWhenLoaded = false;
			
			if(e)
			{
				var key = e.which;
				//console.log("key press:", e);
				
				var escPressed = key == 27;
				if(escPressed)
					return;
					
				if(key == 38) // up
				{
					var $active  = $list.find('.list-group-item.active'),
						$sib = $active.prev('.list-group-item');
					
					if($sib.size() > 0)
					{
						$active.removeClass('active')
						$sib.addClass('active');
						
						var elmTop = $sib.offset().top - $listWrap.offset().top + 15;
						var top = $listWrap.scrollTop();
						var elmHeight = $sib.height();
						
						if(elmTop < 0)
						{
							$sib.get(0).scrollIntoView({
								behavior: "smooth",
								block: "start"
							});
						}
					}
					
					return;
				}
				else
				if(key == 40) // down
				{
					var $active  = $list.find('.list-group-item.active'),
						$sib = $active.next('.list-group-item');
					
					if($sib.size() > 0)
					{
						$active.removeClass('active')
						$sib.addClass('active');
						
						var top = $listWrap.scrollTop();
						var height = $listWrap.height();
						var scrollBottom = top + height;
						
						var elmTop = $sib.offset().top - $listWrap.offset().top + 15;
						var elmHeight = $sib.height();
						var elmBottom = elmTop + elmHeight;
						
	// 					console.log({
	// 						top: top,
	// 						height: height,
	// 						scrollBottom: scrollBottom,
	// 						elmTop: elmTop,
	// 						elmHeight: elmHeight,
	// 						elmBottom: elmBottom,
	// 						flag: elmBottom > height ? true : false
	// 					});
							
						
						if(elmBottom > height)
						{
							$listWrap.scrollTop(
								$listWrap.scrollTop() + elmHeight * 2.5
							);
							/*$sib.get(0).scrollIntoView({
								behavior: "smooth",
								block: "start"
							});*/
						}
					}
					else
					{
						bufferNextPageLoad();
					}
						
					return;
				}
				
				//console.log("paused:",showItemChooser.pauseKeyHandling);
				
				var enterPressed = key == 13;
				if(enterPressed) 
				{
					if(showItemChooser.pauseKeyHandling)
						return;
						
					//console.debug("vis:",$('.db-search-modal').is(':visible'));
					
					var filter = $filter.val();
					filter = filter.replace(/(^\s+|\s+$)/g, '');
				
					// Only click the first entry if its loaded AND
					// if the filter in the box matches the filter
					// used to load current result set
					if(resultSetBuffer.length > 0 && 
						latestResultSetFilter == filter)
					{
						$list.find('.list-group-item.active')
							.first()
							//.addClass('active')
							.click();
							
						return;
					}
					else
					{
						// If either test failed, fall thru to loaded
						// a new result set, and flag the first one
						// to be 'clicked' as soon as its loaded
						clickFirstResultWhenLoaded = true;
					}
					
					//console.debug("enterPressed, resultSetBuffer.length:",resultSetBuffer.length,", clickFirstResultWhenLoaded:",clickFirstResultWhenLoaded);
					
					
				}
			}
			
			//console.log("bufferQueryResults: hit timer, timer for:",dbLookupOptions.ajax.quietMillis,"ms");
			
			// Delay X ms then load the result from the server
			clearTimeout(bufferQueryResults.tid);
			bufferQueryResults.tid = setTimeout(queryResults, dbLookupOptions.ajax.quietMillis);
		};
		
		// NOTE: Using the same tid variable (bufferQueryResults.tid)
		// so we properly stomp on each others timers 
		var bufferNextPageLoad = function() {
			if(bufferNextPageLoad.locked)
				return;
			
			if(!hasMoreResults)
				return;
			
			// Delay X ms then load the result from the server
			clearTimeout(bufferQueryResults.tid);
			bufferQueryResults.tid = setTimeout(nextPageLoad, dbLookupOptions.ajax.quietMillis);
		};
		
		var nextPageLoad = function() {
			currentPage ++;
			loadResultsPage(currentFilter, currentPage);
		};
		
		$listWrap.on('scroll',     checkScrollPosition);
		$filter.on('change',       bufferQueryResults);
		$filter.on('keyup',        bufferQueryResults);
		$filter.on('initial-load', bufferQueryResults);
		
		$filter.on('keyup', function(e) {
			var elm = showItemChooser.currentElm;
			
			if(elm)
			{
				var val = $(this).val();
				
				
				//console.log('form-db-ajax: filter.changed: val:',val,', currentElm:',showItemChooser.currentElm);
				elm.attr('data-current-filter', val);
				
				elm.trigger('filter.changed', e, val);
			}
		});
	}
	
	// From http://stackoverflow.com/questions/20989458/select2-open-dropdown-on-focus
	function select2Focus() {
		var select2 = $(this).data('select2');
		setTimeout(function() {
			if (!select2.opened()) {
				//select2.open();
			}
		}, 0);  
	}
	
	function loadExternalDialog()
	{
		var $btn = $(this),
			url = $btn.attr('data-url');
			
		var $loading = $('<div class="modal spinner-modal" tabindex="-1" role="dialog" aria-hidden="true" style="margin-top:10%">'
			+ '<div class="modal-dialog modal-sm"><div class="modal-content">'
			+ '<div class="modal-body" style="text-align:center;padding:2em">'
			+ '<b><i class="fa fa-spin fa-spinner fa-lg"></i> Please wait, loading data ...</b>'
			+' </div></div></div></div>');
		
		$('.modal').modal('hide');
		
		$loading.modal('show');
		
		/* For now, we'll just redirect to the new URL till we standardize an interface for external dialogs */
		url += (url.indexOf('?') >= 0 ? '&' : '?') + 'url_from=' + encodeURIComponent(window.location.href + '#open:' + $(showItemChooser.currentElm).attr('id'));
		
		window.location.href = url;
		return false;
		
		
		$.ajax({
			url: url,
			
			success: function(result) {
				//console.debug("ajax results:",result);
				
				$loading.hide();
				
				var $result = $(result).find('.body_content_panel form');
				
				if($result.size() <= 0)
				{
					alert("Internal error: Unable to find <form> element from "+url);
					return;
				}
				
				var $dialog = $('.db-add-modal');
				
				$result.find('.btn-cancel')
					.attr('href','#')
					.on('click', function() {
						$dialog.modal('hide');
						$('.modal-backdrop').hide();
						return false;
					});
					
				$result.find('.col-sm-6').removeClass('col-sm-6').addClass('col-sm-12');
				
				$dialog.find('.modal-body').append($result);
				
				$dialog.modal('show');
			},

			error: function(result) {
				
				$loading.hide();
				
				//alert("Error:");
				console.debug(result.responseText);
// 				$(document.body).html('<div class="alert alert-danger style="margin:1em 4em">'+result.responseText+'</div>');
			}
			
		});
		
		return false;
	}
	
	
	window.setupLookupUi = function($jq, hookUrlRoot, openFlag, urlNew, formatters)
	{
		showItemChooser.hookUrlRoot = hookUrlRoot;
		
		// Store overrides if given
		if(formatters)
		{
			if(!dbLookupOptions.optionsOverride[hookUrlRoot])
				dbLookupOptions.optionsOverride[hookUrlRoot] = {};
			
			dbLookupOptions.optionsOverride[hookUrlRoot].formatResult    = formatters.formatResult;
			dbLookupOptions.optionsOverride[hookUrlRoot].formatSelection = formatters.formatSelection;
			
			//console.log("setupLookupUi: formatters for ",hookUrlRoot,": ",dbLookupOptions.optionsOverride[hookUrlRoot]);
		}
		else
		{
			//console.log("setupLookupUi: NO formatters given for ",hookUrlRoot);
		}
		
		// Grab initial list from the server
		primeDbCache(hookUrlRoot);
		
		var pageSize = 25;
// 		$jq.on('change', function() {
// 			
// 			var $input = $(this);
// 			
// 			//checkForBackorder($input);
// 			//updatePricing($input);
// 			
// 			//console.debug("got new id:",id);
// 		});
// 		
		
		//$('select').select2();

// 		var ENABLE_SELECT2 = false;
// 		
// 		var isMobile = window.matchMedia("only screen and (max-width: 1024px)").matches;
// 		if(ENABLE_SELECT2 && 
// 			!isMobile && 
// 			typeof($jq.select2) == 'function')
// 		{
// 			// Used by the ajax code in dbLookupOptions
// 			PAGE_ONE_BASED = true;
// 
// 			var opts = {}; 
// 			for(var key in dbLookupOptions)
// 				opts[key] = dbLookupOptions[key];
// 			
// 			opts.ajax = {};
// 			for(var key in dbLookupOptions.ajax)
// 				opts.ajax[key] = dbLookupOptions.ajax[key];
// 			
// 			opts.ajax.url = hookUrlRoot+'/search';
// 			console.debug("New opts:",opts);
// 			
// 			$jq.select2(opts);
// 			$jq
// 				.one('select2-focus', select2Focus)
// 				.on('select2-blur', function () {
// 					$(this).one('select2-focus', select2Focus)
// 				});
// 				
// 			if(openFlag)
// 				$jq.select2('open');
// 				
// 			//console.log(hookUrlRoot, dbLookupOptions);
// 			
// 			//console.log($jq, $jq.select2);
// 			//$jq.on('select2-blur',  select2Focus);
// 			
// 			return;
// 		}
// 		
		
		var buttonHtml = [
			'<div class="btn-group db-search-btn">',
				'<button type="button" class="btn btn-default dropdown-toggle btn-sm btn-search">',
					'<span class="txt"></span>',
					'<span class="caret"></span>',
				'</button>',
				
				// Can't get styling to work with this to prevent wrapping around 768px, so not using it for now
				//'<button class="btn btn-info btn-sm">...</button>',
				
				// Add item button - removed below if no urlNew
// 					'<button class="btn btn-default btn-new btn-sm">',
// 						'<i class="fa fa-plus-square-o"></i>',
// 						'<span class="btn-text">New Item</span>',
// 					'</button>',
			'</div>'
		].join('');
		
		// Setup the pre-typing buffer
		//showItemChooser.preBuffer = '';
		
		$jq.each(function() {
			var $elm = $(this);
			
			var $widget = $(buttonHtml);
			
			if($elm.attr('data-btn-class'))
				$widget.addClass($elm.attr('data-btn-class'));
			
			//console.log("Creating button for ",this,", is disabled:",$elm.is(':disabled'));
			if($elm.is(':disabled'))
				$widget.addClass('disabled');
			
			$widget.find('.txt').html('<i class="placeholder">(' + ($elm.attr('placeholder') || 'Select an Item') + ')</i>');
			
// 				if(urlNew)
// 					$widget.find('.btn-new')
// 						.attr('data-url', urlNew)
// 						.on('click', loadExternalDialog);
// 				else
// 					$widget.find('.btn-new').remove();
				
			$widget.insertAfter($elm);
			
			/*
			 * if(!$elm.is(':visible') || $elm.attr('type') == 'hidden')
			 *	$widget.hide();
			 */
			
			$elm.hide();
			
			//var initString = $elm.attr('x:initial-string');
			//$widget.find('.txt').html(initString);
			
			var currentVal = $elm.val();
			if(currentVal.match(/^\d+$/))
			{
				dbLookupOptions.initSelection(this, function(result) {
					$widget.find('.txt').html(
						dbLookupOptions.formatSelection(result)
					);
				});
			}
			else
			{
				$widget.find('.txt').html(currentVal ? 
					dbLookupOptions.formatSelection({ value: currentVal }) : 
					'<i class="placeholder">(' + ($elm.attr('placeholder') || 'Select an Item') + ')</i>'
				);
			}
			
			$widget.bind('click', function() {
				if($widget.is('.disabled'))
					return false;
				
				showItemChooser($widget, $elm, hookUrlRoot, urlNew);
			});
			
			$widget.find('.btn').on('keypress', function(e) {
				if($widget.is('.disabled'))
					return false;
				
				//if(!e) 
				//	e = window.event;
					
				//var char = String.fromCharCode(e.which)
				
				// This gets reset once dialog is visible
				//showItemChooser.preBuffer += char;
				
				showItemChooser($widget, $elm, hookUrlRoot, urlNew);
			});
			
			$elm.attr("data-hook-url-root", hookUrlRoot);
			$elm.attr("data-url-new", urlNew);
			
			jQuery.data($elm[0], "db-button", $widget);
			
		});
	};
	
	$.fn.showItemChooser = function(prefill) {
		$(this).each(function() {
			var $this = $(this);
			
			//console.log("$.fn.showItemChooser: this:",this,",  url:",$this.attr("data-hook-url-root"), ", prefill:",prefill);
			
			showItemChooser(
				jQuery.data(this, "db-button"),
				$this, 
				$this.attr("data-hook-url-root"),
				$this.attr("data-url-new"),
				prefill
			);
		});
	};
	
	$.fn.setupItemChooser = function(urlRoot, openFlag, urlNew, formatters) {
		var $self = $(this);
		
		$self.each(function() {
			var $this = $(this);
		
			setupLookupUi(
				$this,
				urlRoot,
				openFlag,
				urlNew,
				formatters
			);
		});
		
		return $self;
	}
	
	function showItemChooser($widget, $elm, hookUrlRoot, urlNew, prefill)
	{
		// dbSearchDialogSetup is called by include()
		//dbSearchDialogSetup();
		
		// $widget is the UI widget (button, etc)
		// $elm is the hidden input element that gets passed back to the server
		
		showItemChooser.currentWidget = $widget;
		showItemChooser.currentElm    = $elm;
		showItemChooser.hookUrlRoot   = hookUrlRoot;
		showItemChooser.urlNew        = urlNew;
		showItemChooser.pauseKeyHandling = true;
		
		setTimeout(function() {
			showItemChooser.pauseKeyHandling = false;
		}, 250);
		
		var $dialog   = $('.db-search-modal');
		var $list     = $dialog.find('.list-group');
		var $listWrap = $dialog.find('.list-group-wrapper');
		var $filter   = $dialog.find('.filter-control');
		var $title    = $dialog.find('.db-search-title');
		
		// Set Title
		$title.html('Choose '+$elm.attr('placeholder'));
		
		// Store placeholder on the dialog for use later in the 'clear item' code
		$title.attr('placeholder', $elm.attr('placeholder'));
		
		// Setup the "Add New Item" button
		if(urlNew)
			$dialog.find('.btn-new')
				.attr('data-url', urlNew)
				.on('click', loadExternalDialog)
				.html('<i class="fa fa-plus-square-o"></i> Add new '+$elm.attr('placeholder') + '...')
				.show();
		else
			$dialog.find('.btn-new').hide();
		
		// Reset dialog
		$list.empty();
		//$list.find('.list-group-item').remove();
		$listWrap.scrollTop(0);
		
		// Reset filter 
		$filter
			.val(prefill ? prefill : '') //showItemChooser.preBuffer)
			// 'initial-load' doesn't buffer the query with a timeout
			// since hopefully we've already got the first page in cache.
			// This just improves the user experience a bit, thats all.
			.trigger('initial-load');
		
		//$dialog.find('.list-group-wrapper').scrollTop(0);

		$dialog.modal({ show: true });
				
		var isMobile = window.matchMedia("only screen and (max-width: 770px)").matches;
		//console.debug(isMobile);
	
		// We dont want to force focus into the filter control on "mobile" devices
		// because that will (could) pop up an onscreen keyboard would would
		// obscure a lot of the list
		if(!isMobile)
			$filter.focus(); //.select();
			
		//showItemChooser.preBuffer = '';
	}
	
	//dbSearchDialogSetup();
	
	setTimeout(function() {
		if(window.location.hash)
		{
			//open:edit-form-student-advisorid
			
			//console.log("found hash:",window.location.hash);
			if(window.location.hash.match(/^#open:/))
			{
				var openId = window.location.hash;
				openId = openId.replace('#open:', '');
				//console.log(openId);
				
				var $elm = $('#' + openId);
				if($elm.size() <= 0)
				{
					console.log("Internal Error: Cannot automatically open '"+openId+'": no element found matching that ID');
					return;
				}
				
				var $btn = $elm.siblings(".db-search-btn");
				
				if($btn.size() <= 0)
				{
					console.log("Internal Error: Cannot automatically open '"+openId+'": no .db-search-btn sibling found adjacent to input');
					return;
				}
				
				$btn.find('.btn').click();
			}
		}
	}, 100);
	
	function databaseLookupHook($elm, urlRoot, formUuid, urlNew)
	{
		//console.log("databaseLookupHook:",urlRoot);
		
		var hookUrlRoot = urlRoot+'/'+formUuid;
		
		setupLookupUi($elm, hookUrlRoot, false, urlNew);
	}
	
	$('.f-ajax-fk[data-bind-uuid]').each(function() {
		
		var $this = $(this);
		databaseLookupHook($this,
			$this.attr('data-url'),
			$this.attr('data-bind-uuid'),
			$this.attr('data-url-new')
		);
	});
	
	$('.f-ajax-fk[data-url-root]').each(function() {
		
		var $this = $(this);
		setupLookupUi($this,
			$this.attr('data-url-root'),
			false,
			$this.attr('data-url-new')
		);
	});
	
});