---
layout: mypost
title: git的各种问题
categories: [疑难杂症]
---

#### 1.错误的git rebase示范   
&emsp;有时候使用git推送数据到服务器出现推送失败的情况，
查询之后发现是远程仓库和本地文件冲突的原因。  
&emsp;然后作为一个新手不清楚git rebase和git merge的区别下贸然使用
了git rebase去解决冲突，然后悲剧了，本地想要提交的文件被删除了！！！   
&emsp;最后使用git rebase --abort撤销回退  







