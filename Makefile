cafe:
	jekyll build
	ghp-import _site -b gitcafe-pages -r cafe -p

pub:
	make cafe
	git ci -am'make:add or fix new post'
	git push origin gh-pages
