---
layout:  page
title: 内核笔记
description: 归档
---
挖了一个大坑，不定时更新，只是一些读书笔记。大多都是概念，例如什么是内核、什么是进程、如何产生中断、时钟是什么。有少量代码，比如进程描述符、调度、内存如何管理，不过也仅是结构体和少量代码。以后可能会深挖代码但不确定，因为不一定有那么多时间。

因为是静态博客，没有搜索，可以用Google或者[通过TAG索引这个笔记](/linux-kernel-architecture/tags/)。

所以这个笔记只是加强和巩固基础，对细节感兴趣的同学可以直接读这两本书[《深入Linux内核架构》](http://book.douban.com/subject/4843567/)，[《深入理解LINUX内核》](http://book.douban.com/subject/1767120/)。

也会不定期从网上搜集一些内容，我本身很搓，可能有各种typo。这篇博客里的所有内容，版权归书的作者所有，我只是记笔记的。这篇博客内容可以任意复制备份和免费发布，但不能用于**任何商业目的**。

数据结构部分只基础说说内核中最常用的数据结构，比如堆和红黑树等等，链表什么的就不写了。一开始理解起来不容易，但会持续写，并对老文章更新。这个东西就是一个持续背书、理解不了、继续读、前面的理解了、回过来再理解的过程。

Linux源代码下载[2.6.32.61](https://www.kernel.org/pub/linux/kernel/v2.6/longterm/v2.6.32/linux-2.6.32.61.tar.xz)。操作系统开发相关网站[OSDEV](http://wiki.osdev.org/Main_Page)。所有的博客里的笔记内容和文章在[Github](https://github.com/GuoJing/linux-kernel-architecture)。

[捐助](/donate/cn/)。

{% for cate in site.categories %}
<div class="year" id="{{ cate[0] }}"><h3>{{ cate[0] }}</h3></div>
<ul class="archive">
    {% for post in cate[1] reversed%}
    <li class="item">
        <a href="{{ site.url }}{{ post.url }}" title="{{ post.title }}">{{ post.title }}</a>
    </li>   
    {% endfor %}
</ul>
{% endfor %}

<div class="year"><h3>搜集</h3></div>
<div class="collect_info">这是我学习过程中找到的一些很不错的资料，仅供学习使用，直接跳转到相应的网站。如果下面文章你不希望被引用，请联系我删除，不好意思。</div>
<ul class="archive">
    {% for article in site.data.articles %}
    <li class="item">
        <a href="{{ article.url }}" title="{{ article.name }}" target="_blank">{{ article.name }}</a>
    </li>
    {% endfor %}
</ul>

<div class="year"><h3>网页</h3></div>
<div class="collect_info">一些其他相关的知识链接，比如汇编、硬件相关的知识。</div>
<ul class="archive">
    {% for link in site.data.links %}
    <li class="item">
        <a href="{{ link.url }}" title="{{ link.name }}" target="_blank">{{ link.name }}</a>
    </li>
    {% endfor %}
</ul>
