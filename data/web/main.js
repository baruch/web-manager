function refreshGSM() {
	$.getJSON("/api/1.0/gsm/status",
			function(data){
			$("#gsm").text(data.strength);
			});
}

function refreshALL() {
	refreshGSM();
}

function deleteGPX(item) {
	$.ajax({
		type: "DELETE",
		url: "/api/1.0/gpx/item?item="+item.data,
		dataType: "json",
		success: function(data){listGPX();}
	});
}

function listGPX() {
	$.getJSON("/api/1.0/gpx/list",
			function(data){
			$("#gpx").empty();
			if (data.length > 0) {
			$.each(data, function(i,item){
				var line = $("<tr/>");
				line.append($("<td/>").append($("<a/>").attr('href', '/api/1.0/gpx/item?item='+item.name).text(item.name)));
				line.append($("<td/>").append(item.size));

				var td = $("<td/>");
				td.append($("<a/>").attr('href', '/api/1.0/gpx/item?format=gpx&item='+item.name).text("As GPX"));
				td.append(' ');
				td.append($("<a/>").attr('href','#').bind("click", item.name, deleteGPX).text('Delete'));
				line.append(td);
				line.appendTo("#gpx");
				});
			} else {
			$("<li/>").text("No gpx traces found").appendTo("#gpxlist");
			}
			}
		 )
}

function tableItems(table, texts, tag) {
	var tr = $("<tr/>");
	$.each(texts, function(i,item) { tr.append($(tag).text(item)); });
	table.append(tr);
}
function tableHeaders(table, texts) {
	tableItems(table, texts, "<th/>");
}

function tableData(table, texts) {
	tableItems(table, texts, "<td/>");
}
function refreshContacts() {
	$("#contacts").empty().text("Loading...");
	$.getJSON("/api/1.0/contacts/list",
			function(data){
				var table = $("<table/>");
				tableHeaders(table, ["Name", "Surname", "Phone", "Mobile"]);

				if (data.length > 0) {
					$.each(data, function(i,item) {
						tableData(table, [item.Name, item.Surname, item.Phone, item.Cell_phone]);
					});
				} else {
					$("<tr/>").attr("rowspan", 4).text("No contacts.").appendTo(table);
				}

				$("#contacts").empty().append(table);
			});
}

function cbMsgList(data) {
	var table = $("<table/>");
	tableHeaders(table, ["Sender", "Content"]);
	if (data.length > 0) {
		try {
			$.each(data, function(i,item){ tableData(table, [item.Sender, item.Content]); });
		} catch (err){
		}
	} else {
		$("<tr/>").attr("rowspan", 2).text("No messages.").appendTo(table);
	}
	$("#messages").empty().append(table);
}
function refreshMessages() {
	$("#messages").empty().text("Loading...");
	$.getJSON("/api/1.0/messages/list", cbMsgList);
}

function init() {
	$("ul.tabs").tabs("div.panes > div", {
		onBeforeClick: function(event,  tabIndex) {
			if (tabIndex == 0) {
				refreshALL();
			} else if (tabIndex == 1) {
				listGPX();
			} else if (tabIndex == 2) {
				refreshContacts();
			} else if (tabIndex == 3) {
				refreshMessages();
			}
			return true;
		}
	});
	refreshALL();
}

$(document).ready(init);
