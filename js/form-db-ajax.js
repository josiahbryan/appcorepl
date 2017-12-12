
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
	include('/appcore/css/form-db-ajax.css?_=3', 'css');

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
				console.log("resultCache: key:",cacheKey,": storing result:",result);
				cache[cacheKey] = result;
			}
			else
			{
				result = cache[cacheKey];
				console.log("resultCache: key:",cacheKey,": returning result:",result);
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

	var _primeCallsPending = [];

	// 20160905 JB: Added 'primeCallsPending' to stagger the hit to the server for multipel primeDbCache calls
	// primarily to allow ajax calls that directly affect the visible UI to get responded to earlier than the prime calls.
	function primeDbCache(urlRoot)
	{
		_primeCallsPending.push(urlRoot);
		//console.log("primeDbCache: (start) _primeCallsPending:",_primeCallsPending);

		if(_primeCallsPending.length > 1)
			return;

		_primeDbCache(urlRoot);
	}


	function setResultsForQuery(urlRoot, filter, list) {

		var result = {
			start: 0,
			limit: Infinity,
			total: Infinity,
			list: list
		};

		var cacheKey = dbLookupOptions.ajax.cacheKey(filter, 0, urlRoot);

		dbLookupOptions.resultCache(cacheKey, result);

		return cacheKey;
	};

	window.setItemChooserResultsForQuery = setResultsForQuery;

	function _primeDbCache(urlRoot)
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
		{
			// Remove current priming call
			_primeCallsPending.shift();

			// If more URLs left to prime, then call back in to this function (the internal _primeDbCache, not the "public" primeDbCache)
			if(_primeCallsPending.length)
				// [0] will be shifted off here when we end it
				_primeDbCache(_primeCallsPending[0]);

			return;
		}

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

				// Remove current priming call
				_primeCallsPending.shift();

				// If more URLs left to prime, then call back in to this function (the internal _primeDbCache, not the "public" primeDbCache)
				if(_primeCallsPending.length)
					// [0] will be shifted off here when we end it
					_primeDbCache(_primeCallsPending[0]);

				//console.log("primeDbCache: (end+) _primeCallsPending:",_primeCallsPending);
			},

			error: function(result) {
				console.log(result.responseText);

				// Remove current priming call
				_primeCallsPending.shift();

				// If more URLs left to prime, then call back in to this function (the internal _primeDbCache, not the "public" primeDbCache)
				if(_primeCallsPending.length)
					// [0] will be shifted off here when we end it
					_primeDbCache(_primeCallsPending[0]);

				//console.log("primeDbCache: (end-) _primeCallsPending:",_primeCallsPending);
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

		var currentPage = 0;
		var currentFilter = '';
		var hasMoreResults = true;

		var specialRows = {
			loading:  $('<a href="#" class="list-group-item special-row alert alert-warning"><i class="fa fa-spin fa-spinner"></i> Loading more results ...</a>')
		};

		// We're using a request queue so that servers that respond
		// with requests out-of-order can be properly sequenced
		var requestQueue = [];
		var requestCounter = 0;

		var resultSetBuffer = [];
		var latestResultSetFilter = '';

		var resultSetCounter = 0;
		var clickFirstResultWhenLoaded = false;

		var updateList = function(processedResults) {

			var $placeholderItem = $(showItemChooser.currentElm);
			var nounTitle =
				($placeholderItem.attr('placeholder') ?
				 $placeholderItem.attr('placeholder') : "Item");

			console.log("placeholderItem: ", showItemChooser.currentElm);

			specialRows.noResult = $('<a href="#" class="list-group-item special-row alert alert-danger">No '+nounTitle.toLowerCase()+' found</a>');

			$filter.attr('placeholder', 'Search for a ' + nounTitle.toLowerCase() + ' by typing the first few letters or a phrase');



			var list       = processedResults.results;
			hasMoreResults = processedResults.more;

			//console.log("updateList: currentPage:",currentPage);

			var emptyList = false;

			if(currentPage == 0)
			{
				$list.empty();

				//return;

				$list.find('.list-group-item').removeClass('active');

				if(!list || list.length <= 0)
				{
					emptyList = true;
					list = [];
				}

				// Add a special item at the very start of the list
				// to "clear" the current item (an option that, when clicked,
				// just clears the value in the box)
				if((!list || !list[0] || !list[0].clearResultItem)
					&& showItemChooser.allowResetItem)
					list.unshift({
						clearResultItem: true
					});

				if((!list || !list.length || !list[0].addNewItem)
					&& showItemChooser.allowNewItem)
					list.unshift({
						addNewItem: true
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

			var specialResetText = "<i>(Reset/Clear currently selected " +  nounTitle + ")</i>";

			var addNewItemText =
				  "<input class='form-control new-item-control' placeholder='Add New " + nounTitle + "'>"
				+ "<button class='btn btn-success btn-add-new-item'"
					+ "style='float: right;margin-top: -31px;margin-right: 3px;'"
					+ "><i class='fa fa-plus add-new-icon'></i></button>";

			for(var i=0; i<list.length; i++)
			{
				var row = list[i];
				var html =
					row.clearResultItem ? specialResetText :
					row.addNewItem ? addNewItemText :
					dbLookupOptions.formatResult(row);

				//var isActive = !row.clearResultItem
				//	&& showItemChooser.currentWidget
				//	&& currentText == html;
				var isActive = row.clearResultItem || row.addNewItem ? false :
					 row.id == currentId ? true: false;

				//console.debug("idx ",i,", this html:",html,", button html:",currentText,", isActive:",isActive);

				var $wrap = $('<a href="#" class="list-group-item"></a>')
					.html(html)
					.attr('x:id',  row.clearResultItem ? '0' : row.id)
					.attr('x:idx', i + startIdx)
					.addClass(row.clearResultItem || row.addNewItem ? 'clear-item' : (isActive ? 'active' : ''))
					.on('click', function(e) {
						e = e || window.event;

						console.log("e.click: ", e.target);
						if(e && e.target && $(e.target).is('input, button, .add-new-icon'))
						{
							if($(e.target).is('.btn-add-new-item, .add-new-icon'))
							{
								var $input = $(this).parent().find('.new-item-control'),
								    $btn   = $(this).parent().find('.btn-add-new-item .fa');
								var val = $input.val();

								$btn.removeClass('fa-plus')
									.addClass('fa-spin')
									.addClass('fa-refresh');
								$input.css('opacity',0.5);

								var url = showItemChooser.hookUrlRoot+'/create';

								if(val != "" && val)
								{
									console.debug("create url:",url,", value=",val);
									$.ajax({
										url: url,
										data: {
											value: val
										},
										success: function(data) {
											if(!data.result || !data)
											{
												console.error("Invalid result:",data);
												alert("Error creating item");
												return;
											}

											// Kill cache because we added new item
											dbLookupOptions.cachedResults = {};

											var result = data.result;

											console.debug("create item: val=",val,", data=",data);

											var string = dbLookupOptions.formatSelection(result);

											$('.db-search-modal').modal('hide');

											if(showItemChooser.currentWidget)
											{
												var w = showItemChooser.currentWidget;

												var title = string.replace(/<[^\>]+>/g,'');

												w.find('.txt').html(string);
												w.find('.btn').attr('title', title);

												showItemChooser.currentElm
													.val(result.id)
													.attr('title', title)
													// Used in our change-detect code attached below
													.attr('data-verified-id', result.id)
													.trigger('change');

												w.find('.btn').focus();

												//console.debug("Clicked row ",idx,", id:",id,", result:",result,", string:",string);
											}

										},
										error: function(error) {
											console.error(error);
											alert("Error creating item");
										}
									});
								}
								else
								{
									alert("Type something to create");
								}

							}

							return false;
						}


						var $elm       = $(this),
							id     = $elm.attr('x:id'),
							idx    = $elm.attr('x:idx'),
							result = resultSetBuffer[idx];

						if(!result)
						{
							if(window.console && console.error)
								console.error("form-db-ajax:click: No result at index ",idx,", resultSetBuffer:",resultSetBuffer);
							return;
						}

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
								// Used in our change-detect code attached below
								.attr('data-verified-id', id)
								.trigger('change');

							w.find('.btn').focus();

							//console.debug("Clicked row ",idx,", id:",id,", result:",result,", string:",string);
						}


						return false;
					});


				$list.append($wrap);

				$wrap.find('.new-item-control').on('keyup', function(e) {
					e = e || window.event;
					if(e && e.which == 13)
					{
						console.log("key up enter");
						$(this).parent().find('.btn-add-new-item').click();
					}

				});


// 				$wrap.find('.btn-add-new').click(function() {
// 					console.log("btn add new click");
// 					var $input = $(this).parent().find('.new-item-control');
// 					var val = $input.val();
// 					console.debug("New btn clicked: ", val);
// 					return false;
// 				});

				if(isActive)
					$wrap.get(0).scrollIntoView();

				resultSetBuffer.push(row);
			}

			if(emptyList && specialRows.noResult)
				$list.append(specialRows.noResult);

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

			if(specialRows.loading)
				specialRows.loading.remove();
			$filter.removeClass('loading');
		};

		var loadResultsPage = function(filter, page, cacheOnly) {

			var data = dbLookupOptions.ajax.data(filter, page);

			//console.debug("loadResultsPage: filter:",filter,", data:",data, ", page:",page);

			if(specialRows.noResult)
				specialRows.noResult.remove();

			//if(page == 0)
				//$list.prepend(specialRows.loading);
			//else
				if(specialRows.loading)
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

					//console.log("search success: ",requestData.cacheKey, " => ", result);
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

			if(specialRows.noResult)
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
						$sib = $active.prev('.list-group-item:not(.clear-item)');

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
						$sib = $active.next('.list-group-item:not(.clear-item)');

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


	window.setLookupFormatters = function(hookUrlRoot, formatters) {
		if(!dbLookupOptions.optionsOverride[hookUrlRoot])
			dbLookupOptions.optionsOverride[hookUrlRoot] = {};

		dbLookupOptions.optionsOverride[hookUrlRoot].formatResult    = formatters.formatResult;
		dbLookupOptions.optionsOverride[hookUrlRoot].formatSelection = formatters.formatSelection;
	};

	window.setupLookupUi = function($jq, hookUrlRoot, openFlag, allowNewItem, formatters, allowResetItem)
	{
		showItemChooser.hookUrlRoot = hookUrlRoot;

		// Store overrides if given
		if(formatters)
		{
			setLookupFormatters(hookUrlRoot, formatters);

			//console.log("setupLookupUi: formatters for ",hookUrlRoot,": ",dbLookupOptions.optionsOverride[hookUrlRoot]);
		}
		else
		{
			//console.log("setupLookupUi: NO formatters given for ",hookUrlRoot);
		}

		// Grab initial list from the server
		if(!primeDbCache.primed)
		{
			/***************************
			 *	NOTE
			 *
			 *	In some deployments, we've had intermitant reports that when multiple fields using form-db-ajax
			 *	are on a page, SOMETIMES clicking on one field shows the list results for another field on the page.
			 *	We have NOT been able to reproduce this in testing in any way. However, the prevaling theory is that
			 *	it has something to do with some sort of race condition or order-of-loading on the page with regards
			 *	to the way the cache is primed. Basically, the theory is that somehow primeDbCache is to blame - but
			 *	without a reproducable problem report, we can't be sure.
			 *
			 *	Therefore, if priming the cache for multiple fields is connected to the root cause, then by limiting
			 *	the cache using a singleton flag (e.g. if .primed is false), we only prime the cache for the FIRST
			 *	field on the page - even if form-db-ajax is used in multiple places on the page.
			 *
			 *	This is a TEMPORARY BAND-AID fix - this does not address the root cause. All this does is (hopefully)
			 *	prevent the problem from affecting the users. This is simply a tradeoff between not priming the cache
			 *	at all and the "phantom bug" - so by priming the cache for only the first field, we still prime
			 *	for "the majority" of pages that just use form-db-ajax once per page. And if they use it more than once,
			 *	then all this means is the subsequent fields will just do JIT loading instead of having a primed cache
			 *	when the user clicks the selection button.
			 *
			 *****************************/


			primeDbCache.primed = true;
			primeDbCache(hookUrlRoot);
		}

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

				// Add item button - removed below if no allowNewItem
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

// 				if(allowNewItem)
// 					$widget.find('.btn-new')
// 						.attr('data-url', allowNewItem)
// 						.on('click', loadExternalDialog);
// 				else
// 					$widget.find('.btn-new').remove();

			$widget.insertAfter($elm);

			$elm.appendTo($widget);

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

			$elm.on('change', function() {
				var $elm = $(this);
				var newId = $elm.val();
				if(newId != $elm.attr('data-verified-id'))
				{
					// Remove initial-string otherwise initSelection will just use that instead of validating new id with server
					$elm.attr('x:initial-string', '');

					showItemChooser.hookUrlRoot = $elm.attr("data-hook-url-root");

					//console.log('Value changed, re-stringifying newId ', newId);

					$widget.find('.txt').html('<i class="fa fa-spin fa-refresh"></i>');

					dbLookupOptions.initSelection($elm, function(result) {
						$widget.find('.txt').html(
							dbLookupOptions.formatSelection(result)
						);
					});
				}
			});

			$widget.bind('click', function(e) {
				if($widget.is('.disabled'))
					return false;

				if(!e)
					e = window.event;

				if(e)
					e.preventDefault();

				showItemChooser($widget, $elm, hookUrlRoot, allowNewItem, null, allowResetItem);

				return false;
			});

			$widget.find('.btn').on('keypress', function(e) {
				if($widget.is('.disabled'))
					return false;

				//if(!e)
				//	e = window.event;

				//var char = String.fromCharCode(e.which)

				// This gets reset once dialog is visible
				//showItemChooser.preBuffer += char;

				showItemChooser($widget, $elm, hookUrlRoot, allowNewItem, null, allowResetItem);
			});

			$elm.attr("data-hook-url-root", hookUrlRoot);
			$elm.attr("data-allow-new", allowNewItem);

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
				$this.attr("data-allow-new"),
				prefill
			);
		});
	};

	$.fn.setupItemChooser = function(urlRoot, openFlag, allowNewItem, formatters, allowResetItem) {
		var $self = $(this);

		$self.each(function() {
			var $this = $(this);

			setupLookupUi(
				$this,
				urlRoot,
				openFlag,
				allowNewItem,
				formatters,
				allowResetItem
			);
		});

		return $self;
	}

	function showItemChooser($widget, $elm, hookUrlRoot, allowNewItem, prefill, allowResetItem)
	{
		// dbSearchDialogSetup is called by include()
		//dbSearchDialogSetup();

		// $widget is the UI widget (button, etc)
		// $elm is the hidden input element that gets passed back to the server

		showItemChooser.currentWidget = $widget;
		showItemChooser.currentElm    = $elm;
		showItemChooser.hookUrlRoot   = hookUrlRoot;
		showItemChooser.allowNewItem  = allowNewItem;
		showItemChooser.allowResetItem = allowResetItem;
		showItemChooser.pauseKeyHandling = true;

		console.error("[showItemChooser]", { $widget, $elm, hookUrlRoot, allowNewItem, prefill, allowResetItem });

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
// 		if(allowNewItem)
// 			$dialog.find('.btn-new')
// 				.attr('data-url', allowNewItem)
// 				.on('click', loadExternalDialog)
// 				.html('<i class="fa fa-plus-square-o"></i> Add new '+$elm.attr('placeholder') + '...')
// 				.show();
// 		else
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

		// Fix for cusor placement based on http://stackoverflow.com/questions/511088/use-javascript-to-place-cursor-at-end-of-text-in-text-input-element
		$filter.focus(function(){
			var that = this;
			setTimeout(function(){
				that.selectionStart = that.selectionEnd = 10000;
				//that.focus();
			}, 0);
		});

		/*
		var isMobile = window.matchMedia("only screen and (max-width: 770px)").matches;
		//console.debug(isMobile);

		// We dont want to force focus into the filter control on "mobile" devices
		// because that will (could) pop up an onscreen keyboard would would
		// obscure a lot of the list
		if(!isMobile)

		*/
			//$filter.focus(); //.select();

		setTimeout(function() {
			$filter.focus();
		}, 100);
		//showItemChooser.preBuffer = '';
	}

	//dbSearchDialogSetup();

// 	setTimeout(function() {
// 		if(window.location.hash)
// 		{
// 			//open:edit-form-student-advisorid
//
// 			//console.log("found hash:",window.location.hash);
// 			if(window.location.hash.match(/^#open:/))
// 			{
// 				var openId = window.location.hash;
// 				openId = openId.replace('#open:', '');
// 				//console.log(openId);
//
// 				var $elm = $('#' + openId);
// 				if($elm.size() <= 0)
// 				{
// 					console.log("Internal Error: Cannot automatically open '"+openId+'": no element found matching that ID');
// 					return;
// 				}
//
// 				var $btn = $elm.siblings(".db-search-btn");
//
// 				if($btn.size() <= 0)
// 				{
// 					console.log("Internal Error: Cannot automatically open '"+openId+'": no .db-search-btn sibling found adjacent to input');
// 					return;
// 				}
//
// 				$btn.find('.btn').click();
// 			}
// 		}
// 	}, 100);

	function databaseLookupHook($elm, urlRoot, formUuid, allowNewItem, allowResetItem)
	{
		//console.log("databaseLookupHook:",urlRoot);

		var hookUrlRoot = urlRoot+'/'+formUuid;

		setupLookupUi($elm, hookUrlRoot, false, allowNewItem, null, allowResetItem);
	}

	$('.f-ajax-fk[data-bind-uuid]').each(function() {

		var $this = $(this);
		databaseLookupHook($this,
			$this.attr('data-url'),
			$this.attr('data-bind-uuid'),
			$this.attr('data-allow-new') == 'true',
			$this.attr('data-allow-reset') == 'true',
		);
	});

	$('.f-ajax-fk[data-url-root]').each(function() {

		var $this = $(this);
		setupLookupUi($this,
			$this.attr('data-url-root'),
			false,
			$this.attr('data-allow-new') == 'true',
			null,
			$this.attr('data-allow-reset') == 'true',
		);
	});

});
