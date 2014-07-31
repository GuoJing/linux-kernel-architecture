---
layout:  page
title: 标记
description: 标记
---
方便索引：

<div class="tagcloud">
{% for tag in site.tags %}
<span class="{{ c }}"><a href="#{{ tag[0] }}">{{ tag[0] }}</a></span>
{% endfor %}
</div>

{% for tag in site.tags %}
<div class="year" id="{{ tag[0] }}"><h3>{{ tag[0] }}</h3></div>
<ul class="archive">
    {% for post in tag[1] reversed%}
    <li class="item">
        <a href="{{ site.url }}{{ post.url }}" title="{{ post.title }}">{{ post.title }}</a>
    </li>   
    {% endfor %}
</ul>
{% endfor %}