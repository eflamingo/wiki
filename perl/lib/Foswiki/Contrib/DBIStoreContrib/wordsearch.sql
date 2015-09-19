SELECT th1."key", th1.topic_key, th1.revision, th1.timestamp_epoch, th1.web_key, 
		bsname."value" as topic_name, bscontent.summary as summary, webs1.current_web_name as web_name, th1.user_key,
			mp."name" ||':'|| mp."value" as permissions
FROM foswiki."Topic_History" th1 
	INNER JOIN foswiki."Blob_Store" bsname ON bsname."key" = th1.topic_name
	INNER JOIN foswiki."Blob_Store" bscontent ON bscontent."key" = th1.topic_content
	INNER JOIN foswiki."Webs" webs1 ON webs1."key" = th1.web_key
	INNER JOIN foswiki."Topics" topics ON topics.link_to_latest = th1."key"
	LEFT OUTER JOIN foswiki."MetaPreferences_History" mp ON mp.topic_history_key = th1."key" AND mp."type" = 'Set' AND (mp."name" = 'ALLOWTOPICVIEW' OR mp."name" = 'DENYTOPICVIEW')
	WHERE bscontent.value_vector @@ to_tsquery('running')
	ORDER BY web_name ASC, topic_name ASC, timestamp_epoch ASC;


    * Main.AdminGroup?
    * Main.AdminUser?
    * Main.BaseGroup?
    * Main.BlogAdminGroup?
    * Main.BlogAuthorGroup?
    * Main.GenPDFLatexForm?
    * Main.GroupTemplate?
    * Main.GroupViewTemplate?
    * Main.NobodyGroup?
    * Main.ProjectContributor?
    * Main.RegistrationAgent?
    * Main.SitePreferences?
    * Main.SlionSkinUserViewTemplate?
    * Main.UnknownUser?
    * Main.UnprocessedRegistrations?
    * Main.UnprocessedRegistrationsLog?
    * Main.UserForm?
    * Main.UserHomepageHeader?
    * Main.UserList?
    * Main.UserListByDateJoined?
    * Main.UserListByLocation?
    * Main.UserListHeader?
    * Main.WebAtom?
    * Main.WebChanges?
    * Main.WebCreateNewTopic?
    * Main.WebHome?
    * Main.WebIndex?
    * Main.WebLeftBarExample?
    * Main.WebNotify?
    * Main.WebOrphans?
    * Main.WebPreferences?
    * Main.WebRss?
    * Main.WebSearch?
    * Main.WebSearchAdvanced?
    * Main.WebStatistics?
    * Main.WebTopicList?
    * Main.WikiGroups?
    * Main.WikiGuest?
 	