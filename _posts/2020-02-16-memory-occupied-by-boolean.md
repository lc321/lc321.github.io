---
layout: mypost
title: Java基础知识疑点
categories: [学习笔记]
---

**1.boolean占字节数**   
&emsp;Java中定义有八大数据类型,除了boolean类型外其他都有明确的内存占用字节数,
那么boolean类型究竟占用多少字节?  
&emsp;Java虚拟机规范》一书中的描述：“虽然定义了boolean这种数据类型，但是只对它提供了非常有限的支持。
在Java虚拟机中没有任何供boolean值专用的字节码指令，Java语言表达式所操作的boolean值，在编译之后都使用
Java虚拟机中的int数据类型来代替，而boolean数组将会被编码成Java虚拟机的byte数组，每个元素boolean元素占8位”.

&emsp;因此可以得出boolean类型单独使用时占4个字节,在数组中占1个字节 
 
**2.Java中无参构造方法的作用**   
&emsp;Java程序在执行一个子类程序时,默认会调用父类无参数构造方法,除非使用super()调用特定构造方法.
如果父类中只定义了有参数的构造方法,而子类构造方法没有使用super()来调用父类构造方法时,将发生编译错误,
因为在父类中找不到无参的构造方法.

**3.hashCode 与 equals**    
* 为什么要有 hashCode   
&emsp;hashCode() 的作用是获取哈希码，也称为散列码；它实际上是返回一个int整数。这个哈希码的作用是
确定该对象在哈希表中的索引位置.以HashSet 如何检查重复为例:当你把对象加入 HashSet 时，
HashSet会先计算对象的hashcode值来判断对象加入的位置，同时也会与其他已经加入的对象的
hashcode 值作比较，如果没有相符的hashcode，HashSet会假设对象没有重复出现。但是如果发现有
相同 hashcode 值的对象，这时会调用 equals()方法来检查 hashcode 相等的对象是否真的相同。
如果两者相同，HashSet 就不会让其加入操作成功。如果不同的话，就会重新散列到其他位置。
这样我们就大大减少了equals 的次数，相应就大大提高了执行速度。

* 为什么重写equals时必须重写hashCode方法？  
hashCode()与equals()的相关规定:  
&emsp;两个对象相等，则hashcode一定也是相同的  
&emsp;两个对象相等，即equals返回true  
&emsp;两个对象hashcode相等，他们不一定相等  
重写了equals,而不重写hashcode可能会出现两个对象相等（两对象equals为true）但hashcode不等的情况。
因此，equals 方法被覆盖过，则 hashCode 方法也必须被覆盖

**4.IO的方式（简单解释）**  
IO的方式通常分为BIO、NIO、AIO：  
* BIO
一对应，一请求，一应答模式（即一个连接一个线程）  
* NIO  
多路复用，一个请求一个线程模式  
* AIO  
即NIO2，一个有效请求一个线程模式  

**5.this与super注意**  
* this()与super()应放在构造器首行，否则编译器会报错  
* this、super不能用在static方法中（this和super是属于对象范畴的东西，而静态方法是属于类范畴的东西）  

**6.**








