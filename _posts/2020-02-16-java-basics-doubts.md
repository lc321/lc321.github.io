---
layout: mypost
title: Java基础知识疑点
categories: [Java]
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

**6.Arraylist.asList()使用**  
我们可以使用Arraylist.asList()将一个数组转换为一个List集合，但实际上其底层仍是数组：  
asList的返回对象是一个Arrays的内部类，并没有实现集合的修改方法。Arrays.asList体现的
是适配器模式，只是转换接口，后台仍是数组。  
> String[] str = snew String[]("app","pen");  
> List list = Arrays.asList(str);
使用list.add("other");运行时异常  
使用str[0] = "another";list.get(0)也随之修改  
如何正确的将数组转换为ArrayList?  
> List list = new ArrayList<>(Arrays.asList("a","b","c"));

**7.get和post两种请求的区别**  
GET和POST的底层都是TCP/IP，并无差别。但是由于HTTP的规定和浏览器/服务器的限制，
导致他们在应用过程中体现出一些不同。比如：  
- GET在浏览器回退时是无害的，而POST会再次提交请求。
- GET产生的URL地址可以被Bookmark，而POST不可以
- GET请求会被浏览器主动cache，而POST不会，除非手动设置。
- GET请求只能进行url编码，而POST支持多种编码方式。
- GET请求参数会被完整保留在浏览器历史记录里，而POST中的参数不会被保留。
- GET请求在URL中传送的参数是有长度限制的，而POST么有。
- 对参数的数据类型，GET只接受ASCII字符，而POST没有限制。
- GET比POST更不安全，因为参数直接暴露在URL上，所以不能用来传递敏感信息。
- GET参数通过URL传递，POST放在Request body中。  
GET和POST还有一个重大区别：  
GET产生一个TCP数据包；POST产生两个TCP数据包。  
对于GET方式的请求，浏览器会把http header和data一并发送出去，服务器响应200（返回数据）；  
而对于POST，浏览器先发送header，服务器响应100 continue，浏览器再发送data，服务器响应200 ok（返回数据）。  


**8.会话跟踪技术**  
- Cookie
- URL重写
- 隐藏的表单域
- HttpSession  
Cookie与Session的区别：  
- 应用场景不同。  
	- Cookie 一般用来保存用户信息，例如1.登陆过的用户信息；2.存放token值
	- Session 的主要作用就是通过服务端记录用户的状态。例如购物车
- 保存的地址不同
	- Cookie 数据保存在客户端(浏览器端)
	- Session 数据保存在服务器端
	
**9.反射机制**  
JAVA 反射机制是指在运行状态中，对于任意一个类，都能够知道这个类的所有属性和方法；
对于任意一个对象，都能够调用它的任意一个方法和属性。  
- Class.forName()传入类的路径获取Class对象
- 反射的应用场景
	- JDBC连接使用Class.forName()通过反射加载数据库驱动
	- Spring IOC(动态加载管理Bean)以及AOP(动态代理)
	- 动态配置实例属性
	











