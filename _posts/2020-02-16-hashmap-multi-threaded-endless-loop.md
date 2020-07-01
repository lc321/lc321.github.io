---
layout: mypost
title: HashMap多线程导致死循环
categories: [Java]
---

### 问题
HashMap在并发情况下的rehash会造成元素之间形成一个循环链表，我们在这里研究一下原因：  
直接上源代码(rehash)：  
  
### Hashmap.put
```
public V put(K key, V value)
{
    ......
    //算Hash值
    int hash = hash(key.hashCode());
    int i = indexFor(hash, table.length);
    //如果该key已被插入，则替换掉旧的value （链接操作）
    for (Entry<K,V> e = table[i]; e != null; e = e.next) {
        Object k;
        if (e.hash == hash && ((k = e.key) == key || key.equals(k))) {
            V oldValue = e.value;
            e.value = value;
            e.recordAccess(this);
            return oldValue;
        }
    }
    modCount++;
    //该key不存在，需要增加一个结点
    addEntry(hash, key, value, i);
    return null;
}
```

### 检查容量是否超标
```
void addEntry(int hash, K key, V value, int bucketIndex)
{
    Entry<K,V> e = table[bucketIndex];
    table[bucketIndex] = new Entry<K,V>(hash, key, value, e);
    //查看当前的size是否超过了我们设定的阈值threshold，如果超过，需要resize
    if (size++ >= threshold)
        resize(2 * table.length);
}
```

### 创建一个更大的hash表然后迁移数据
```
void resize(int newCapacity)
{
    Entry[] oldTable = table;
    int oldCapacity = oldTable.length;
    ......
    //创建一个新的Hash Table
    Entry[] newTable = new Entry[newCapacity];
    //将Old Hash Table上的数据迁移到New Hash Table上
    transfer(newTable);
    table = newTable;
    threshold = (int)(newCapacity * loadFactor);
}
```

### 迁移过程
```
void transfer(Entry[] newTable)
{
    Entry[] src = table;
    int newCapacity = newTable.length;
    //下面这段代码的意思是：
    //  从OldTable里摘一个元素出来，然后放到NewTable中
    for (int j = 0; j < src.length; j++) {
        Entry<K,V> e = src[j];
        if (e != null) {
            src[j] = null;
            do {
                Entry<K,V> next = e.next;
                int i = indexFor(e.hash, newCapacity);
                e.next = newTable[i];
                newTable[i] = e;
                e = next;
            } while (e != null);
        }
    }
}
```
**重点在循环体**

### 画图演示  
**单线程下的rehash**  
- 假设hash算法就是用key mod 表大小（即数组长度）
- 假设old hash表size=2,当key=3,7,5数据插入时会像这样：  
	![](hashmap_1.png)
- 单线程正常rehash,size变为4，数据重新插入，会变成这样：
	![](hashmap_2.png)  

**并发下的rehash**  
- 条件同上
- 假设有2个线程
- 重点观察循环体  
	```
	do {
		Entry<K,V> next = e.next;//假设线程一执行到此处被挂起
		int i = indexFor(e.hash, newCapacity);
		e.next = newTable[i];
		newTable[i] = e;
		e = next;
	} while (e != null);
	```
- 线程一第一步被挂起，而线程二执行完成，于是：  
	![](hashmap_3.png)
- 接着线程一被调度执行，于是：
	![](hashmap_4.png)
	![](hashmap_5.png)
	![](hashmap_6.png)
	结合代码观察变化
- 线程一继续工作下一循环，先把key(7)摘下来：
	![](hashmap_7.png)
	![](hashmap_8.png)
	环形链接出现
	![](hashmap_9.png)
	![](hashmap_10.png)  

### 总结  
hashmap不支持并发，如果要使用并发应该使用ConcurrentHashmap.

参考：[https://coolshell.cn/articles/9606.html](https://coolshell.cn/articles/9606.html)
	
	
	









