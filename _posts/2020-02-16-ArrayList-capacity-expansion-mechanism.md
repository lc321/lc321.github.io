---
layout: mypost
title: ArrayList的扩容机制
categories: [Java]
---

### ArrayList属性及构造方法  
```
// 默认容量是10
private static final int DEFAULT_CAPACITY = 10;
// 如果容量为0的时候，就返回这个数组
private static final Object[] EMPTY_ELEMENTDATA = {};
// 使用默认容量10时，返回这个数组
private static final Object[] DEFAULTCAPACITY_EMPTY_ELEMENTDATA = {};
// 元素存放的数组
transient Object[] elementData;
// 元素的个数
private int size;

/**
 *默认构造函数，使用初始容量10构造一个空列表(无参数构造)
 */
public ArrayList() {
	this.elementData = DEFAULTCAPACITY_EMPTY_ELEMENTDATA;
}

/**
 * 带初始容量参数的构造函数。（用户自己指定容量）
 */
public ArrayList(int initialCapacity) {
	if (initialCapacity > 0) {//初始容量大于0
		//创建initialCapacity大小的数组
		this.elementData = new Object[initialCapacity];
	} else if (initialCapacity == 0) {//初始容量等于0
		//创建空数组
		this.elementData = EMPTY_ELEMENTDATA;
	} else {//初始容量小于0，抛出异常
		throw new IllegalArgumentException("Illegal Capacity: "+
										   initialCapacity);
	}
}

/**
 *构造包含指定collection元素的列表，这些元素利用该集合的迭代器按顺序返回
 *如果指定的集合为null，throws NullPointerException。 
 */
public ArrayList(Collection<? extends E> c) {
	elementData = c.toArray();
	if ((size = elementData.length) != 0) {
		// c.toArray might (incorrectly) not return Object[] (see 6260652)
		if (elementData.getClass() != Object[].class)
			elementData = Arrays.copyOf(elementData, size, Object[].class);
	} else {
		// replace with empty array.
		this.elementData = EMPTY_ELEMENTDATA;
	}
}
```

可以看出ArrayList有三个构造方法：
- 无参构造方法，设置elementData为DEFAULTCAPACITY_EMPTY_ELEMENTDATA，即实际上初始化赋值的是一个空数组。
当真正对数组进行添加元素操作时，才真正分配容量。即向数组中添加第一个元素时，数组容量扩为10。
- 如果传入初始容量，会判断这个传入的值，如果大于0，就new一个新的Object数组，如果等于0，
就直接设置elementData为EMPTY_ELEMENTDATA
- 如果传入一个Collection，则调用toArray()方法变成数组来初始化。

### ArrayList扩容实现  
**1.要扩容当然要添加元素**
```
/**
 * 将指定的元素追加到此列表的末尾。 
 */
public boolean add(E e) {
	ensureCapacityInternal(size + 1);  // Increments modCount!!
	elementData[size++] = e;
	return true;
}
```

**2.添加元素之前，调用ensureCapacityInternal方法**
```
private void ensureCapacityInternal(int minCapacity) {
	ensureExplicitCapacity(calculateCapacity(elementData, minCapacity));
}

/**
 * 得到最小扩容量
 */
private static int calculateCapacity(Object[] elementData, int minCapacity) {
	if (elementData == DEFAULTCAPACITY_EMPTY_ELEMENTDATA) {
		// 获取默认的容量和传入参数的较大值
		return Math.max(DEFAULT_CAPACITY, minCapacity);
	}
	return minCapacity;
}

/**
 * 判断是否达到扩容条件
 */
private void ensureExplicitCapacity(int minCapacity) {
	modCount++;

	// overflow-conscious code
	if (minCapacity - elementData.length > 0)
		//真正的扩容方法grow()
		grow(minCapacity);
}
```

- 当我们add第一个元素时，数组容量还为0，然后执行calculateCapacity()得到最小扩容量minCapacity
为10，此时ensureExplicitCapacity()中判断达到扩容条件执行grow()方法。
- 当我们add第二个元素时，minCapacity=2，在ensureExplicitCapacity()中判断minCapacity - elementData.length<0
未达到扩容条件。
- 直到添加第11个元素时才开始扩容

**3.grow方法**
```
private void grow(int minCapacity) {
	// oldCapacity为旧容量，newCapacity为新容量
	int oldCapacity = elementData.length;
	// newCapacity新容量为旧容量的1.5倍
	int newCapacity = oldCapacity + (oldCapacity >> 1);
	// 当newCapacity小于所需最小容量，那么将所需最小容量赋值给newCapacity
	if (newCapacity - minCapacity < 0)
		newCapacity = minCapacity;
	// newCapacity大于ArrayList的所允许的最大容量则执行hugeCapacity()
	if (newCapacity - MAX_ARRAY_SIZE > 0)
		newCapacity = hugeCapacity(minCapacity);
	// minCapacity is usually close to size, so this is a win:
	elementData = Arrays.copyOf(elementData, newCapacity);
}
```

- Arrays.copyOf(elementData, newCapacity)实际的数组扩容方法，
elementData：要复制的数组；newCapacity：要复制的长度










