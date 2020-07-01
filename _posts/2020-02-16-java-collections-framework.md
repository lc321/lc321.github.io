---
layout: mypost
title: Java集合框架
categories: [Java]
---

**1.ArrayList与LinkedList**   
- ArrayList与LinkedList都不保证线程安全
- ArrayList底层使用object数组；LinkedList底层使用双向链表
- ArrayList支持快速随机访问，而LinkedList不支持（ArrayList实现了
RandomAccess 接口但是RandomAccess 接口只是标识，表明了他具有快速随机访问功能）
- 对于新增和删除操作add和remove，LinedList比较占优势，只需要对指针进行修改即可，
而ArrayList要移动数据来填补被删除的对象的空间
- ArrayList的空 间浪费主要体现在在list列表的结尾会预留一定的容量空间，而LinkedList
的空间花费则体现在它的每一个元素都需要消耗比ArrayList更多的空间（因为要存放直接后继
和直接前驱以及数据）  

**2.ArrayList的扩容机制**
[从源码解读ArrayList扩容机制](http://localhost:4000/posts/2020/02/16/ArrayList-capacity-expansion-mechanism.html)

**3.HashMap 和 Hashtable 的区别**
- HashMap是非线程安全的，HashTable是线程安全的
- HashMap中，null可以作为键但只能有一个，可以有一个或多个键所对应的值为null;HashTable中不允许有null
- HashMap默认初始容量16，每次扩容2倍；Hashtable默认初始容量11，每次扩容2n+1倍
- HashMap底层使用数组链表+红黑树实现，当链表长度大于8时，将链表转化为红黑树；当链表长度小于6时，又把红黑树转化成链表

**4.HashMap多线程死循环**
[图解HashMap为什么不支持并发](http://localhost:4000/posts/2020/02/16/hashmap-multi-threaded-endless-loop.html)  

**5.ConcurrentHashMap与HashTable的区别**
- HashTable底层数组+链表；ConcurrentHashMap与HashMap类似
- jdk1.7,ConcurrentHashMap使用分段锁，1.8以后并发控制使用sychronized和CAS实现；HashTable则使用全表锁


**6.红黑树**








